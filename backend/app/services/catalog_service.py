"""Publishing: guide listings and guide accounts reach travellers.

Before this module a guide could write listings all day and nothing reached the
public site: ``GET /experiences`` served seeded content plus host-owned rows,
``GET /guides/{id}`` read the legacy ``guides`` display table, and
``POST /bookings`` assigned every request to one hard-coded guide account.
This service is the single place that turns a **live** guide listing into a
catalogue row, and the single place that resolves a catalogue id back to the
guide who owns it — so browsing, the detail page and booking cannot drift.

Identity in the catalogue is namespaced, because three id spaces share the
``experience_id`` column:

===================  ==========================  =====================
Row                  Public ``id``               Public ``slug``
===================  ==========================  =====================
Seeded content       small ints (1…)             ``kathmandu-…``
Host experience      ``100000 + host_exp.id``    ``host-…``
Guide listing        ``200000 + listing.id``     ``listing-…``
===================  ==========================  =====================

Guide *profiles* are namespaced the same way (``300000 + user.id``) so they can
never be mistaken for a legacy ``guides`` row.

Visibility rule: a listing is public when it is active **and** its guide
account is active. Pausing a listing (``PATCH /guide/listings/{id}`` with
``is_active: false``) therefore removes it from the catalogue immediately, and
its guide updates with it (see ``GuideDashboardService.list_public_updates``).
"""

from __future__ import annotations

import re
import unicodedata
from typing import Iterable, List, Optional, Sequence

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.guide_listing import GuideListing, GuideProfile
from app.models.review import Review
from app.models.user import User

# Catalogue id ranges — see the module docstring.
PUBLIC_LISTING_ID_OFFSET = 200_000
PUBLIC_GUIDE_ID_OFFSET = 300_000

# Slug prefix so a listing URL can never collide with a seeded experience slug.
PUBLIC_LISTING_SLUG_PREFIX = "listing-"

# The three guide listing categories, mapped onto the category values the
# public catalogue already serves so the Explore filter chips keep working.
_PUBLIC_CATEGORY = {
    "trekking": "Adventure",
    "tour": "Cultural",
    "specialized": "Workshop",
}

# Listings have no hero image of their own; a category-appropriate photo keeps
# cards looking whole without pretending it is a photo of this guide's trip.
_FALLBACK_IMAGE = {
    "Adventure": "https://images.unsplash.com/photo-1544735716-392fe2489ffa?auto=format&fit=crop&w=800&q=80",
    "Cultural": "https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=800&q=80",
    "Workshop": "https://images.unsplash.com/photo-1556910103-1c02745aae4d?auto=format&fit=crop&w=800&q=80",
}
_DEFAULT_IMAGE = _FALLBACK_IMAGE["Cultural"]


def slugify(value: str) -> str:
    """A URL-safe ASCII slug: ``"Annapurna Circuit — 8 days"`` → ``annapurna-circuit-8-days``."""
    normalised = unicodedata.normalize("NFKD", value or "")
    ascii_only = normalised.encode("ascii", "ignore").decode("ascii").lower()
    dashes = re.sub(r"[^a-z0-9]+", "-", ascii_only).strip("-")
    return dashes[:60].strip("-") or "experience"


def public_listing_id(listing_id: int) -> int:
    return PUBLIC_LISTING_ID_OFFSET + int(listing_id)


def listing_id_from_public_id(experience_id: int) -> Optional[int]:
    """Reverse :func:`public_listing_id`; ``None`` for any other id space."""
    if isinstance(experience_id, bool) or not isinstance(experience_id, int):
        return None
    if experience_id < PUBLIC_LISTING_ID_OFFSET + 1:
        return None
    if experience_id >= PUBLIC_GUIDE_ID_OFFSET:
        return None
    return experience_id - PUBLIC_LISTING_ID_OFFSET


def public_guide_id(user_id: int) -> int:
    return PUBLIC_GUIDE_ID_OFFSET + int(user_id)


def guide_id_from_public_id(guide_id: int) -> Optional[int]:
    if isinstance(guide_id, bool) or not isinstance(guide_id, int):
        return None
    if guide_id < PUBLIC_GUIDE_ID_OFFSET + 1:
        return None
    return guide_id - PUBLIC_GUIDE_ID_OFFSET


class CatalogService:
    """Read-side joins that make guide work visible to travellers."""

    def __init__(self, db: Session):
        self.db = db

    # ------------------------------------------------------------------ #
    # Writing side: slugs                                                #
    # ------------------------------------------------------------------ #
    def unique_slug(self, title: str, exclude_id: Optional[int] = None) -> str:
        """A slug no other listing holds.

        Generated once at creation and never regenerated on rename, so a link a
        traveller shared keeps resolving after the guide edits the title.
        """
        base = slugify(title)
        candidate, suffix = base, 2
        while True:
            query = self.db.query(GuideListing.id).filter(
                GuideListing.slug == candidate
            )
            if exclude_id is not None:
                query = query.filter(GuideListing.id != exclude_id)
            if query.first() is None:
                return candidate
            candidate = f"{base}-{suffix}"[:70]
            suffix += 1

    # ------------------------------------------------------------------ #
    # Catalogue rows                                                     #
    # ------------------------------------------------------------------ #
    def _live_listings(self, city: Optional[str] = None) -> List[GuideListing]:
        query = (
            self.db.query(GuideListing)
            .join(User, GuideListing.guide_user_id == User.id)
            .filter(
                GuideListing.is_active.is_(True),
                User.is_active.is_(True),
            )
        )
        if city:
            query = query.filter(func.lower(GuideListing.city) == city.strip().lower())
        return query.order_by(GuideListing.created_at.desc()).all()

    def published_experiences(self, city: Optional[str] = None) -> List[dict]:
        """Catalogue rows for every live guide listing."""
        return self._rows(self._live_listings(city))

    def published_experience(self, slug: str) -> Optional[dict]:
        """One catalogue row from ``listing-<slug>``; ``None`` when not live."""
        if not slug.startswith(PUBLIC_LISTING_SLUG_PREFIX):
            return None
        wanted = slug[len(PUBLIC_LISTING_SLUG_PREFIX) :]
        listing = (
            self.db.query(GuideListing)
            .join(User, GuideListing.guide_user_id == User.id)
            .filter(
                GuideListing.slug == wanted,
                GuideListing.is_active.is_(True),
                User.is_active.is_(True),
            )
            .first()
        )
        if listing is None:
            return None
        return self._rows([listing])[0]

    def listing_for_experience(self, experience_id: int) -> Optional[GuideListing]:
        """The live listing behind a catalogue id, or ``None``.

        Called by the booking service: a listing id means the request belongs
        to that listing's guide, anything else keeps the legacy single-guide
        routing.
        """
        listing_id = listing_id_from_public_id(experience_id)
        if listing_id is None:
            return None
        return (
            self.db.query(GuideListing)
            .join(User, GuideListing.guide_user_id == User.id)
            .filter(
                GuideListing.id == listing_id,
                GuideListing.is_active.is_(True),
                User.is_active.is_(True),
            )
            .first()
        )

    def guide_for_listing(self, listing: GuideListing) -> User:
        """The (active) guide account that owns a listing."""
        from fastapi import HTTPException

        guide = self.db.get(User, listing.guide_user_id)
        if guide is None or not guide.is_active:
            raise HTTPException(status_code=404, detail="Experience not found")
        return guide

    # ------------------------------------------------------------------ #
    # Public guide profiles                                              #
    # ------------------------------------------------------------------ #
    def public_guide(self, guide_id: int) -> Optional[dict]:
        """A guide account as a traveller profile, for namespaced ids only."""
        user_id = guide_id_from_public_id(guide_id)
        if user_id is None:
            return None
        user = self.db.get(User, user_id)
        if user is None or not user.is_active:
            return None
        return self._guide_payloads([user]).get(user.id)

    def public_guides(self, city: Optional[str] = None) -> List[dict]:
        """Guide accounts that onboarded, newest profile first.

        Only guides with a saved profile are listed: without one there is no
        display name, bio or city to show a traveller, and a bare email would
        leak an account detail that is not profile content.
        """
        query = (
            self.db.query(User)
            .join(GuideProfile, GuideProfile.guide_user_id == User.id)
            .filter(User.is_active.is_(True))
        )
        users = query.order_by(GuideProfile.updated_at.desc().nullslast()).all()
        payloads = self._guide_payloads(users)
        rows = [payloads[u.id] for u in users if u.id in payloads]
        if city:
            wanted = city.strip().lower()
            rows = [r for r in rows if any(c.lower() == wanted for c in r["cities"])]
        return rows

    # ------------------------------------------------------------------ #
    # Internals                                                          #
    # ------------------------------------------------------------------ #
    def _ratings(self, experience_ids: Sequence[int]) -> dict[int, tuple[float, int]]:
        """``{experience_id: (average, count)}`` in one query."""
        if not experience_ids:
            return {}
        rows = (
            self.db.query(
                Review.experience_id,
                func.avg(Review.rating),
                func.count(Review.id),
            )
            .filter(Review.experience_id.in_(list(experience_ids)))
            .group_by(Review.experience_id)
            .all()
        )
        return {
            int(exp): (float(avg or 0.0), int(count or 0)) for exp, avg, count in rows
        }

    def _guide_payloads(self, users: Iterable[User]) -> dict[int, dict]:
        """Build every guide payload in a handful of queries, not per row."""
        user_list = [u for u in users if u is not None]
        if not user_list:
            return {}
        user_ids = [int(u.id) for u in user_list]
        profiles = {
            p.guide_user_id: p
            for p in self.db.query(GuideProfile)
            .filter(GuideProfile.guide_user_id.in_(user_ids))
            .all()
        }
        listings = (
            self.db.query(GuideListing)
            .filter(
                GuideListing.guide_user_id.in_(user_ids),
                GuideListing.is_active.is_(True),
            )
            .all()
        )
        # A guide's rating is the pooled rating of their published trips: the
        # only reviews that exist are left by travellers who completed one.
        ratings = self._ratings([public_listing_id(listing.id) for listing in listings])
        by_guide: dict[int, list[int]] = {}
        for listing in listings:
            by_guide.setdefault(listing.guide_user_id, []).append(
                public_listing_id(listing.id)
            )

        payloads: dict[int, dict] = {}
        for user in user_list:
            profile = profiles.get(int(user.id))
            keys = by_guide.get(int(user.id), [])
            total = sum(ratings[k][1] for k in keys if k in ratings)
            weighted = sum(ratings[k][0] * ratings[k][1] for k in keys if k in ratings)
            average = round(weighted / total, 2) if total else 0.0
            display = (profile.display_name or "").strip() if profile else ""
            joined = f"{user.firstName or ''} {user.lastName or ''}".strip()
            payloads[int(user.id)] = {
                "id": public_guide_id(int(user.id)),
                "name": display or joined or "Local guide",
                "image": user.avatar_url or "",
                "role": "Local guide",
                "rating": average,
                "reviews": total,
                "bio": ((profile.bio if profile else None) or user.bio or ""),
                "languages": list((profile.languages if profile else []) or []),
                # The platform records no verification for guide accounts, so
                # the badge stays off rather than being implied by signup.
                "verified": False,
                "livesIn": user.region,
                "cities": list((profile.cities if profile else []) or []),
                "gallery": [],
                "is_active": bool(user.is_active),
            }
        return payloads

    def _rows(self, listings: Sequence[GuideListing]) -> List[dict]:
        if not listings:
            return []
        guide_ids = {listing.guide_user_id for listing in listings}
        users = {
            u.id: u
            for u in self.db.query(User).filter(User.id.in_(list(guide_ids))).all()
        }
        payloads = self._guide_payloads(users.values())
        ratings = self._ratings([public_listing_id(x.id) for x in listings])

        rows: List[dict] = []
        for listing in listings:
            host = payloads.get(int(listing.guide_user_id))
            if host is None:
                # Owner deactivated between the two queries — leave it out
                # rather than serve a row with no guide to book.
                continue
            public_id = public_listing_id(int(listing.id))
            average, count = ratings.get(public_id, (0.0, 0))
            category = _PUBLIC_CATEGORY.get(
                (listing.category or "").lower(), "Cultural"
            )
            spots = max(
                int(listing.max_guests or 0) - int(listing.booked_guests or 0), 0
            )
            rows.append(
                {
                    "id": public_id,
                    "slug": f"{PUBLIC_LISTING_SLUG_PREFIX}{listing.slug}",
                    "title": listing.title,
                    # The guide's own photo wins; the category photo is a
                    # placeholder for a listing that has not uploaded one.
                    "heroImage": listing.hero_image
                    or _FALLBACK_IMAGE.get(category, _DEFAULT_IMAGE),
                    "description": listing.description,
                    "price": float(listing.price or 0.0),
                    "duration": listing.duration,
                    "rating": round(average, 2) if count else None,
                    "reviews": count,
                    "city": listing.city,
                    "category": category,
                    "host": host,
                    "guides": [host],
                    # Extras only a real listing can answer, so the detail
                    # screen can show what the traveller is actually buying.
                    "listingId": int(listing.id),
                    "area": listing.area,
                    "difficulty": listing.difficulty,
                    "meetingPoint": listing.meeting_point,
                    "itinerary": listing.itinerary,
                    "maxGuests": int(listing.max_guests or 0),
                    "availableSpots": spots,
                }
            )
        return rows
