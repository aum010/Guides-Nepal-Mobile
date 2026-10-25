"""Business logic for the guide dashboard (listings, capacity, status, onboarding)."""

from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from datetime import datetime, timedelta, timezone

from app.models.guide_listing import GuideListing, GuideProfile, GuideStatusUpdate
from app.models.user import User
from app.schemas.guide_dashboard import (
    GuideListingCapacityUpdate,
    GuideListingCreate,
    GuideListingUpdate,
    GuideOnboardingCreate,
    GuideStatusCreate,
)


def _listing_to_dict(listing: GuideListing) -> dict:
    available = max((listing.max_guests or 0) - (listing.booked_guests or 0), 0)
    occupancy = (
        round((listing.booked_guests or 0) / listing.max_guests * 100)
        if listing.max_guests
        else 0
    )
    return {
        "id": listing.id,
        "title": listing.title,
        "category": listing.category,
        "city": listing.city,
        "area": listing.area,
        "description": listing.description,
        "itinerary": listing.itinerary,
        "meeting_point": listing.meeting_point,
        "duration": listing.duration,
        "difficulty": listing.difficulty,
        "price": listing.price,
        "max_guests": listing.max_guests,
        "is_active": listing.is_active,
        "booked_guests": listing.booked_guests or 0,
        "available_spots": available,
        "occupancy_pct": occupancy,
    }


class GuideDashboardService:
    def __init__(self, db: Session):
        self.db = db

    def list_listings(self, guide_id: int) -> List[dict]:
        rows = (
            self.db.query(GuideListing)
            .filter(GuideListing.guide_user_id == guide_id)
            .order_by(GuideListing.created_at.desc())
            .all()
        )
        return [_listing_to_dict(row) for row in rows]

    def create_listing(self, guide: User, payload: GuideListingCreate) -> dict:
        listing = GuideListing(guide_user_id=guide.id, **payload.model_dump())
        self.db.add(listing)
        self.db.commit()
        self.db.refresh(listing)
        return _listing_to_dict(listing)

    def update_listing(
        self, guide_id: int, listing_id: int, payload: GuideListingUpdate
    ) -> dict:
        listing = self._get_owned_listing(guide_id, listing_id)
        data = payload.model_dump(exclude_unset=True)
        new_max = data.get("max_guests")
        if new_max is not None and new_max < (listing.booked_guests or 0):
            raise HTTPException(
                status_code=422, detail="max_guests cannot be below booked guests"
            )
        for key, value in data.items():
            setattr(listing, key, value)
        self.db.commit()
        self.db.refresh(listing)
        return _listing_to_dict(listing)

    def delete_listing(self, guide_id: int, listing_id: int) -> None:
        listing = self._get_owned_listing(guide_id, listing_id)
        self.db.delete(listing)
        self.db.commit()

    def update_capacity(
        self, guide_id: int, listing_id: int, payload: GuideListingCapacityUpdate
    ) -> dict:
        listing = self._get_owned_listing(guide_id, listing_id)
        if payload.max_guests is not None:
            if payload.max_guests < (listing.booked_guests or 0):
                raise HTTPException(
                    status_code=422, detail="max_guests cannot be below booked guests"
                )
            listing.max_guests = payload.max_guests
        if payload.booked_delta:
            new_booked = (listing.booked_guests or 0) + payload.booked_delta
            if new_booked < 0 or new_booked > (listing.max_guests or 0):
                raise HTTPException(
                    status_code=422, detail="booked guests out of capacity bounds"
                )
            listing.booked_guests = new_booked
        self.db.commit()
        self.db.refresh(listing)
        return _listing_to_dict(listing)

    def _get_owned_listing(self, guide_id: int, listing_id: int) -> GuideListing:
        listing = (
            self.db.query(GuideListing)
            .filter(
                GuideListing.id == listing_id, GuideListing.guide_user_id == guide_id
            )
            .first()
        )
        if not listing:
            raise HTTPException(status_code=404, detail="Listing not found")
        return listing

    def list_status(self, guide_id: int, limit: int = 20) -> List[dict]:
        rows = (
            self.db.query(GuideStatusUpdate)
            .filter(GuideStatusUpdate.guide_user_id == guide_id)
            .order_by(GuideStatusUpdate.created_at.desc())
            .limit(limit)
            .all()
        )
        out = []
        for row in rows:
            out.append(
                {
                    "id": row.id,
                    "update_type": row.update_type,
                    "message": row.message,
                    "listing_id": row.listing_id,
                    "area": row.area,
                    "event_date": (
                        row.event_date.isoformat() if row.event_date else None
                    ),
                    "current_capacity": row.current_capacity,
                    "max_capacity": row.max_capacity,
                    "is_active": row.is_active,
                    "created_at": (
                        row.created_at.isoformat() if row.created_at else None
                    ),
                }
            )
        return out

    def list_public_updates(self, city: Optional[str], limit: int = 20) -> List[dict]:
        """Active, current updates that a traveller browsing [city] should see.

        Scoped by **city, not by guide identity**, because the two guide
        systems in this database are disjoint: ``guide_status_updates`` is
        keyed by a guide's ``users`` row, while the profiles travellers browse
        at ``GET /guides/{id}`` come from the legacy ``guides`` catalog and
        have no link back to a user account (only the Host dashboard's
        ``host_guides`` ever creates one, and no seed does). Scoping by city
        is also what travellers actually navigate by.

        An update qualifies when it:

        * belongs to a guide who lists [city] on their onboarding profile, or
          is attached to an active listing in [city];
        * is still active (a guide can unpublish an update without deleting it);
        * is not stale — a dated update must not be past its day, and an
          undated one must be less than [max_age_days] old, so a traveller
          never reads "two spots left" about a trip that already left;
        * is not an internal ``booking`` note, which is written for the guide's
          own workflow rather than for travellers.

        Rows are fetched newest-first and truncated once [limit] matches are
        collected, so the limit applies to visible updates rather than to
        candidates.
        """
        max_age_days = 14
        now = datetime.now(timezone.utc)
        wanted = city.strip().lower() if city else None

        rows = (
            self.db.query(GuideStatusUpdate)
            .filter(GuideStatusUpdate.is_active.is_(True))
            .order_by(GuideStatusUpdate.created_at.desc())
            .all()
        )

        listing_ids = {r.listing_id for r in rows if r.listing_id is not None}
        listings = (
            {
                listing.id: listing
                for listing in self.db.query(GuideListing)
                .filter(GuideListing.id.in_(listing_ids))
                .all()
            }
            if listing_ids
            else {}
        )

        guide_ids = {r.guide_user_id for r in rows}
        profiles = (
            {
                p.guide_user_id: p
                for p in self.db.query(GuideProfile)
                .filter(GuideProfile.guide_user_id.in_(guide_ids))
                .all()
            }
            if guide_ids
            else {}
        )
        users = (
            {u.id: u for u in self.db.query(User).filter(User.id.in_(guide_ids)).all()}
            if guide_ids
            else {}
        )

        def _guide_name(guide_id: int) -> str:
            profile = profiles.get(guide_id)
            if profile and profile.display_name and profile.display_name.strip():
                return profile.display_name.strip()
            user = users.get(guide_id)
            if user:
                joined = f"{user.firstName or ''} {user.lastName or ''}".strip()
                if joined:
                    return joined
            return "A local guide"

        def _is_current(row: GuideStatusUpdate) -> bool:
            if row.event_date is not None:
                stamp = row.event_date
                if stamp.tzinfo is None:
                    stamp = stamp.replace(tzinfo=timezone.utc)
                return stamp.date() >= now.date()
            if row.created_at is None:
                return True
            created = row.created_at
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            return created >= now - timedelta(days=max_age_days)

        def _cities_for(row: GuideStatusUpdate) -> List[str]:
            """The cities this update is relevant to."""
            listing = listings.get(row.listing_id) if row.listing_id else None
            if listing is not None:
                # A paused listing is hidden from travellers, so its updates
                # go with it rather than outliving the listing.
                return [listing.city] if listing.is_active else []
            profile = profiles.get(row.guide_user_id)
            if not profile:
                return []
            # Deduplicate while keeping the guide's declared order.
            return list(dict.fromkeys(c for c in (profile.cities or []) if c))

        out: List[dict] = []
        for row in rows:
            if row.update_type == "booking":
                continue
            if not _is_current(row):
                continue

            cities = _cities_for(row)
            if wanted is not None:
                if not any(c.strip().lower() == wanted for c in cities):
                    continue

            listing = listings.get(row.listing_id) if row.listing_id else None
            out.append(
                {
                    "id": row.id,
                    "update_type": row.update_type,
                    "message": row.message,
                    "area": row.area,
                    "event_date": (
                        row.event_date.isoformat() if row.event_date else None
                    ),
                    "current_capacity": row.current_capacity,
                    "max_capacity": row.max_capacity,
                    "created_at": (
                        row.created_at.isoformat() if row.created_at else None
                    ),
                    "guide_name": _guide_name(row.guide_user_id),
                    "listing_title": listing.title if listing else None,
                    "cities": cities,
                }
            )
            if len(out) >= limit:
                break
        return out

    def post_status(self, guide: User, payload: GuideStatusCreate) -> dict:
        if payload.listing_id is not None:
            self._get_owned_listing(int(guide.id), payload.listing_id)
        row = GuideStatusUpdate(guide_user_id=guide.id, **payload.model_dump())
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return self.list_status(int(guide.id), limit=50)[0]

    def delete_status(self, guide_id: int, status_id: int) -> None:
        row = (
            self.db.query(GuideStatusUpdate)
            .filter(
                GuideStatusUpdate.id == status_id,
                GuideStatusUpdate.guide_user_id == guide_id,
            )
            .first()
        )
        if not row:
            raise HTTPException(status_code=404, detail="Status update not found")
        self.db.delete(row)
        self.db.commit()

    def get_onboarding(self, guide_id: int) -> Optional[dict]:
        profile = (
            self.db.query(GuideProfile)
            .filter(GuideProfile.guide_user_id == guide_id)
            .first()
        )
        return self._profile_to_dict(profile) if profile else None

    def save_onboarding(self, guide: User, payload: GuideOnboardingCreate) -> dict:
        profile = (
            self.db.query(GuideProfile)
            .filter(GuideProfile.guide_user_id == guide.id)
            .first()
        )
        data = payload.model_dump()
        if profile:
            for key, value in data.items():
                setattr(profile, key, value)
        else:
            profile = GuideProfile(guide_user_id=guide.id, **data)
            self.db.add(profile)
        self.db.commit()
        self.db.refresh(profile)
        return self._profile_to_dict(profile)

    @staticmethod
    def _profile_to_dict(profile: GuideProfile) -> dict:
        return {
            "guide_user_id": profile.guide_user_id,
            "display_name": profile.display_name,
            "expertise_areas": profile.expertise_areas or [],
            "cities": profile.cities or [],
            "languages": profile.languages or [],
            "bio": profile.bio,
            "years_experience": profile.years_experience,
            "default_max_guests": profile.default_max_guests,
            "onboarding_completed": profile.onboarding_completed,
        }
