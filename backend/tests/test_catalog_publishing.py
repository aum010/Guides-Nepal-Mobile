"""Publishing: a guide's listing is a real, bookable catalogue experience.

Three things used to be true at once and wrong: a guide's listings never
reached travellers, ``GET /guides`` could not show a real guide account, and
every booking — whatever the experience — was assigned to one hard-coded
account. These tests pin the behaviour that replaced it:

- a live listing appears in ``GET /experiences`` as ``listing-<slug>`` with its
  own guide as host, and disappears the moment it is paused;
- the booking goes to the guide who owns the listing, takes seats from that
  listing, and gives them back on cancellation or rejection;
- seeded content keeps working exactly as before.
"""

import os

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.security import create_access_token, get_password_hash
from app.core.storage import UPLOADS_ROOT
from app.models.booking import Booking
from app.models.guide_listing import GuideListing, GuideProfile
from app.models.user import User

EXPERIENCES = "/api/v1/experiences"
GUIDES = "/api/v1/guides"
BOOKINGS = "/api/v1/bookings"


def _guide(db: Session, email: str, **profile: dict) -> User:
    user = User(
        email=email,
        hashed_password=get_password_hash("Guide@2024"),
        firstName=email.split("@")[0].title(),
        lastName="Gurung",
        role="guide",
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    db.add(GuideProfile(guide_user_id=user.id, onboarding_completed=True, **profile))
    db.commit()
    return user


def _listing(db: Session, guide: User, **overrides: dict) -> GuideListing:
    fields = {
        "guide_user_id": guide.id,
        "slug": f"sunrise-hike-{guide.id}",
        "title": "Sunrise hike to Sarangkot",
        "category": "trekking",
        "city": "Pokhara",
        "area": "Sarangkot ridge",
        "description": "An easy pre-dawn walk to the ridge above the lake.",
        "itinerary": "Pickup 4:30 am, ridge by sunrise, tea, walk down.",
        "meeting_point": "Lakeside taxi stand",
        "duration": "4 hours",
        "difficulty": "Moderate",
        "price": 45.0,
        "max_guests": 4,
        "is_active": True,
    }
    fields.update(overrides)
    row = GuideListing(**fields)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _traveler(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPassword123!",
            "firstName": "Trek",
            "lastName": "Traveller",
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _guide_headers(guide: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(guide.id)}"}


def _book(client: TestClient, headers: dict, experience_id: int, **overrides) -> dict:
    body = {
        "experience_id": experience_id,
        "experience_title": "Sunrise hike to Sarangkot",
        "city": "Pokhara",
        "date": "2026-12-01T05:00:00",
        "guests": 2,
        "price": 90.0,
    }
    body.update(overrides)
    return client.post(f"{BOOKINGS}/", json=body, headers=headers)


class TestCatalogue:
    def test_a_live_listing_is_a_catalogue_experience(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(
            db_session,
            "pemba@example.com",
            display_name="Pemba Gurung",
            cities=["Pokhara"],
            languages=["Nepali", "English"],
            bio="Fifteen years on the Annapurna trails.",
        )
        listing = _listing(db_session, guide)

        response = client.get(EXPERIENCES)
        assert response.status_code == 200, response.text
        rows = [row for row in response.json() if row["slug"].startswith("listing-")]
        assert len(rows) == 1
        row = rows[0]

        # A namespaced id, so a listing can never collide with a seeded row.
        assert row["id"] == 200000 + listing.id
        assert row["slug"] == f"listing-{listing.slug}"
        assert row["title"] == "Sunrise hike to Sarangkot"
        # trekking maps onto a category the Explore chips actually filter by.
        assert row["category"] == "Adventure"
        assert row["city"] == "Pokhara"
        assert row["price"] == 45.0
        assert row["listingId"] == listing.id
        assert row["maxGuests"] == 4
        assert row["availableSpots"] == 4
        assert row["meetingPoint"] == "Lakeside taxi stand"

        # The host is the guide account itself, addressable as a profile.
        assert row["host"]["id"] == 300000 + guide.id
        assert row["host"]["name"] == "Pemba Gurung"
        assert row["host"]["cities"] == ["Pokhara"]
        assert row["host"]["languages"] == ["Nepali", "English"]
        # The platform records no verification, so the badge is not implied.
        assert row["host"]["verified"] is False

    def test_the_detail_page_resolves_the_listing_slug(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "detail@example.com", display_name="Detail Guide")
        listing = _listing(db_session, guide)

        response = client.get(f"{EXPERIENCES}/listing-{listing.slug}")
        assert response.status_code == 200, response.text
        assert response.json()["id"] == 200000 + listing.id
        assert response.json()["itinerary"].startswith("Pickup 4:30 am")

        assert client.get(f"{EXPERIENCES}/listing-does-not-exist").status_code == 404

    def test_pausing_a_listing_hides_it_and_its_detail_page(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "pause@example.com", display_name="Pause Guide")
        listing = _listing(db_session, guide)
        assert client.get(f"{EXPERIENCES}/listing-{listing.slug}").status_code == 200

        listing.is_active = False
        db_session.commit()

        rows = [
            row
            for row in client.get(EXPERIENCES).json()
            if row["slug"] == f"listing-{listing.slug}"
        ]
        assert rows == []
        assert client.get(f"{EXPERIENCES}/listing-{listing.slug}").status_code == 404

    def test_a_deactivated_guide_takes_their_listings_with_them(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "gone@example.com", display_name="Gone Guide")
        listing = _listing(db_session, guide)
        guide.is_active = False
        db_session.commit()

        slugs = [row["slug"] for row in client.get(EXPERIENCES).json()]
        assert f"listing-{listing.slug}" not in slugs

    def test_listings_are_city_filtered(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "city@example.com", display_name="City Guide")
        _listing(db_session, guide, city="Pokhara")
        _listing(
            db_session,
            guide,
            slug="bhaktapur-pottery",
            title="Pottery workshop in Bhaktapur",
            category="specialized",
            city="Bhaktapur",
        )

        pokhara = [
            r for r in client.get(EXPERIENCES, params={"city": "Pokhara"}).json()
        ]
        slugs = [row["slug"] for row in pokhara if row["slug"].startswith("listing-")]
        assert slugs == ["listing-sunrise-hike-%d" % guide.id]

        # Specialized work maps onto the Workshop category chip.
        bhaktapur = [
            row
            for row in client.get(EXPERIENCES, params={"city": "Bhaktapur"}).json()
            if row["slug"].startswith("listing-")
        ]
        assert bhaktapur[0]["category"] == "Workshop"

    def test_sorting_by_rating_survives_an_unreviewed_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        # A listing with no reviews has a null rating; sorting must not raise.
        guide = _guide(db_session, "sort@example.com", display_name="Sort Guide")
        _listing(db_session, guide)

        response = client.get(EXPERIENCES, params={"sort": "rating"})
        assert response.status_code == 200, response.text
        assert response.json() != []

    def test_the_guide_profile_is_public(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(
            db_session,
            "public-guide@example.com",
            display_name="Public Guide",
            cities=["Kathmandu"],
            languages=["English"],
            bio="Kathmandu heritage walks.",
        )

        listed = client.get(GUIDES, params={"city": "Kathmandu"}).json()
        match = [g for g in listed if g["id"] == 300000 + guide.id]
        assert match and match[0]["name"] == "Public Guide"

        profile = client.get(f"{GUIDES}/{300000 + guide.id}")
        assert profile.status_code == 200, profile.text
        assert profile.json()["bio"] == "Kathmandu heritage walks."
        assert client.get(f"{GUIDES}/{300000 + guide.id + 500}").status_code == 404


class TestBookingRouting:
    def test_a_listing_booking_goes_to_the_guide_who_owns_it(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "owner@example.com", display_name="Owner Guide")
        listing = _listing(db_session, guide)
        headers = _traveler(client, "routing@example.com")

        response = _book(client, headers, 200000 + listing.id)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["guide_user_id"] == guide.id
        assert body["guide_listing_id"] == listing.id
        # The booking names the guide account (which is what the traveller
        # messages), while the catalogue card shows the profile display name.
        assert body["guide_name"] == "Owner Gurung", body
        assert body["experience_id"] == 200000 + listing.id

        # The seats are held by the listing straight away.
        db_session.refresh(listing)
        assert listing.booked_guests == 2

        # And the guide sees the request in their own workspace.
        assignments = client.get(
            "/api/v1/guide/bookings", headers=_guide_headers(guide)
        )
        assert assignments.status_code == 200, assignments.text
        assert [row["id"] for row in assignments.json()] == [body["id"]]

    def test_two_guides_keep_their_own_bookings(
        self, client: TestClient, db_session: Session
    ) -> None:
        first = _guide(db_session, "first@example.com", display_name="First Guide")
        second = _guide(db_session, "second@example.com", display_name="Second Guide")
        first_listing = _listing(db_session, first, slug="first-trek")
        second_listing = _listing(db_session, second, slug="second-trek")
        assert first_listing.id != second_listing.id

        headers = _traveler(client, "two-guides@example.com")
        first_booking = _book(client, headers, 200000 + first_listing.id)
        second_booking = _book(
            client,
            headers,
            200000 + second_listing.id,
            date="2026-12-05T05:00:00",
        )
        assert first_booking.json()["guide_user_id"] == first.id
        assert second_booking.json()["guide_user_id"] == second.id

        assert [
            r["id"]
            for r in client.get(
                "/api/v1/guide/bookings", headers=_guide_headers(first)
            ).json()
        ] == [first_booking.json()["id"]]

    def test_capacity_is_enforced_and_reported(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(
            db_session, "capacity@example.com", display_name="Capacity Guide"
        )
        listing = _listing(db_session, guide, max_guests=3)
        headers = _traveler(client, "capacity-traveller@example.com")

        assert _book(client, headers, 200000 + listing.id, guests=4).status_code == 409

        first = _book(client, headers, 200000 + listing.id, guests=2)
        assert first.status_code == 200, first.text

        # Two of three seats are gone; the one left is visible, and asking for
        # two is refused rather than silently oversold.
        availability = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-12-09", "experience_id": 200000 + listing.id},
            headers=headers,
        )
        assert availability.json()["spots_left"] == 1

        assert (
            _book(
                client,
                headers,
                200000 + listing.id,
                guests=2,
                date="2026-12-10T05:00:00",
            ).status_code
            == 409
        )

        # Fill the last seat, then the listing reports itself full everywhere.
        assert (
            _book(
                client,
                headers,
                200000 + listing.id,
                guests=1,
                date="2026-12-11T05:00:00",
            ).status_code
            == 200
        )
        full = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-12-20", "experience_id": 200000 + listing.id},
            headers=headers,
        )
        assert full.json() == {"available": False, "status": "full", "spots_left": 0}

    def test_cancelling_returns_the_seats_once(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "cancel@example.com", display_name="Cancel Guide")
        listing = _listing(db_session, guide, max_guests=4)
        headers = _traveler(client, "cancel-traveller@example.com")
        booking = _book(client, headers, 200000 + listing.id, guests=2).json()

        assert (
            client.post(
                f"{BOOKINGS}/{booking['id']}/cancel", headers=headers
            ).status_code
            == 200
        )
        db_session.refresh(listing)
        assert listing.booked_guests == 0

        # A repeated cancel must not hand back another two seats.
        assert (
            client.post(
                f"{BOOKINGS}/{booking['id']}/cancel", headers=headers
            ).status_code
            == 200
        )
        db_session.refresh(listing)
        assert listing.booked_guests == 0

    def test_a_guide_declining_frees_the_seats(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "decline@example.com", display_name="Decline Guide")
        listing = _listing(db_session, guide, max_guests=2)
        headers = _traveler(client, "decline-traveller@example.com")
        booking = _book(client, headers, 200000 + listing.id, guests=2).json()
        db_session.refresh(listing)
        assert listing.booked_guests == 2

        declined = client.patch(
            f"/api/v1/guide/bookings/{booking['id']}",
            json={"status": "rejected"},
            headers=_guide_headers(guide),
        )
        assert declined.status_code == 200, declined.text
        db_session.refresh(listing)
        assert listing.booked_guests == 0

        # Re-opening the request takes them back.
        accepted = client.patch(
            f"/api/v1/guide/bookings/{booking['id']}",
            json={"status": "accepted"},
            headers=_guide_headers(guide),
        )
        assert accepted.status_code == 200, accepted.text
        db_session.refresh(listing)
        assert listing.booked_guests == 2

    def test_a_seeded_experience_still_uses_the_catalog_guide(
        self, client: TestClient, db_session: Session
    ) -> None:
        fallback = User(
            email="guide@guides-nepal.com",
            firstName="Catalog",
            lastName="Guide",
            hashed_password=get_password_hash("TestPassword123!"),
            role="guide",
            is_active=True,
        )
        db_session.add(fallback)
        db_session.commit()

        headers = _traveler(client, "seeded@example.com")
        body = _book(client, headers, 4, date="2026-12-02T05:00:00").json()
        assert body["guide_user_id"] == fallback.id
        assert body["guide_listing_id"] is None

    def test_guests_must_be_within_reason(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "bounds@example.com", display_name="Bounds Guide")
        listing = _listing(db_session, guide)
        headers = _traveler(client, "bounds-traveller@example.com")

        assert _book(client, headers, 200000 + listing.id, guests=0).status_code == 422
        assert _book(client, headers, 200000 + listing.id, guests=-3).status_code == 422

    def test_a_booking_row_is_linked_to_the_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "link@example.com", display_name="Link Guide")
        listing = _listing(db_session, guide)
        headers = _traveler(client, "link-traveller@example.com")
        _book(client, headers, 200000 + listing.id)

        row = db_session.query(Booking).one()
        assert row.guide_listing_id == listing.id
        assert row.guide_user_id == guide.id


class TestListingSlugs:
    def test_slugs_are_generated_and_unique(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "slug@example.com", display_name="Slug Guide")
        headers = _guide_headers(guide)
        payload = {
            "title": "Annapurna Base Camp Trek",
            "category": "trekking",
            "city": "Pokhara",
            "description": "Twelve days to the sanctuary and back.",
            "duration": "12 days",
            "difficulty": "Challenging",
            "price": 1200.0,
            "max_guests": 6,
        }

        first = client.post("/api/v1/guide/listings", json=payload, headers=headers)
        second = client.post("/api/v1/guide/listings", json=payload, headers=headers)
        assert first.status_code == 201, first.text
        assert second.status_code == 201, second.text
        assert first.json()["slug"] == "annapurna-base-camp-trek"
        assert second.json()["slug"] == "annapurna-base-camp-trek-2"
        assert first.json()["public_slug"] == "listing-annapurna-base-camp-trek"
        assert first.json()["is_public"] is True

        # The generated slug is what the public catalogue serves.
        detail = client.get(f"{EXPERIENCES}/listing-annapurna-base-camp-trek")
        assert detail.status_code == 200, detail.text
        assert detail.json()["title"] == "Annapurna Base Camp Trek"

    def test_renaming_keeps_the_published_url(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "rename@example.com", display_name="Rename Guide")
        headers = _guide_headers(guide)
        created = client.post(
            "/api/v1/guide/listings",
            json={
                "title": "Old Title Trek",
                "category": "tour",
                "city": "Kathmandu",
                "description": "A walk through the old town.",
                "duration": "3 hours",
                "difficulty": "Easy",
                "price": 30.0,
                "max_guests": 8,
            },
            headers=headers,
        ).json()

        updated = client.patch(
            f"/api/v1/guide/listings/{created['id']}",
            json={"title": "New Title Walk"},
            headers=headers,
        )
        assert updated.status_code == 200, updated.text
        # The slug is stable: a link a traveller shared keeps working.
        assert updated.json()["slug"] == "old-title-trek"
        assert client.get(f"{EXPERIENCES}/listing-old-title-trek").status_code == 200


class TestListingPhoto:
    """A listing photo is validated, stored where it is served, and cleaned up."""

    PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64

    @staticmethod
    def _clean(url: str | None) -> None:
        if not url:
            return
        relative = url.removeprefix("/uploads/")
        path = UPLOADS_ROOT / relative
        if path.is_file():
            path.unlink()
        parent = path.parent
        if parent.is_dir() and not os.listdir(parent):
            parent.rmdir()

    def test_upload_sets_the_photo_on_the_listing_and_the_catalogue(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "photo@example.com", display_name="Photo Guide")
        listing = _listing(db_session, guide)
        headers = _guide_headers(guide)

        response = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("ridge.png", self.PNG, "image/png")},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        body = response.json()
        url = body["hero_image"]
        try:
            assert url.startswith(f"/uploads/listings/{listing.id}/")
            assert url.endswith(".png")

            # Stored where the app serves it: the upload path and the mount
            # used to disagree, which made every uploaded URL a 404.
            served = client.get(url)
            assert served.status_code == 200, served.text
            assert served.content == self.PNG

            catalogue = client.get(f"{EXPERIENCES}/listing-{listing.slug}")
            assert catalogue.json()["heroImage"] == url
        finally:
            self._clean(url)

    def test_replacing_the_photo_removes_the_old_file(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "replace@example.com", display_name="Replace Guide")
        listing = _listing(db_session, guide)
        headers = _guide_headers(guide)

        first = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("one.png", self.PNG, "image/png")},
            headers=headers,
        ).json()["hero_image"]
        second = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("two.png", self.PNG, "image/png")},
            headers=headers,
        ).json()["hero_image"]
        try:
            assert first != second
            assert not (UPLOADS_ROOT / first.removeprefix("/uploads/")).exists()
            assert (UPLOADS_ROOT / second.removeprefix("/uploads/")).exists()
        finally:
            self._clean(first)
            self._clean(second)

    def test_only_images_are_accepted(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "types@example.com", display_name="Types Guide")
        listing = _listing(db_session, guide)
        headers = _guide_headers(guide)
        endpoint = f"/api/v1/guide/listings/{listing.id}/photo"

        wrong_type = client.post(
            endpoint,
            files={"file": ("notes.txt", b"hello", "text/plain")},
            headers=headers,
        )
        assert wrong_type.status_code == 415

        # A lying Content-Type is caught by the signature check.
        not_really_png = client.post(
            endpoint,
            files={"file": ("fake.png", b"<html>hello</html>", "image/png")},
            headers=headers,
        )
        assert not_really_png.status_code == 422
        assert "not a valid image" in not_really_png.json()["detail"]

        too_big = client.post(
            endpoint,
            files={
                "file": (
                    "huge.png",
                    self.PNG + b"0" * (5 * 1024 * 1024),
                    "image/png",
                )
            },
            headers=headers,
        )
        assert too_big.status_code == 413

        db_session.refresh(listing)
        assert listing.hero_image is None

    def test_a_stranger_cannot_set_the_photo(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _guide(db_session, "photo-owner@example.com", display_name="Owner")
        stranger = _guide(db_session, "photo-thief@example.com", display_name="Thief")
        listing = _listing(db_session, owner)

        response = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("x.png", self.PNG, "image/png")},
            headers=_guide_headers(stranger),
        )
        assert response.status_code == 404
        db_session.refresh(listing)
        assert listing.hero_image is None

    def test_the_photo_can_be_cleared_but_not_pointed_at_a_url(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "clear@example.com", display_name="Clear Guide")
        listing = _listing(db_session, guide)
        headers = _guide_headers(guide)
        url = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("x.png", self.PNG, "image/png")},
            headers=headers,
        ).json()["hero_image"]

        refused = client.patch(
            f"/api/v1/guide/listings/{listing.id}",
            json={"hero_image": "https://example.com/tracker.gif"},
            headers=headers,
        )
        assert refused.status_code == 422
        assert "Upload the photo" in refused.json()["detail"]

        cleared = client.patch(
            f"/api/v1/guide/listings/{listing.id}",
            json={"hero_image": None},
            headers=headers,
        )
        assert cleared.status_code == 200, cleared.text
        assert cleared.json()["hero_image"] is None
        assert not (UPLOADS_ROOT / url.removeprefix("/uploads/")).exists()

    def test_deleting_a_listing_removes_its_photos(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "delete-photo@example.com", display_name="Deleter")
        listing = _listing(db_session, guide)
        headers = _guide_headers(guide)
        url = client.post(
            f"/api/v1/guide/listings/{listing.id}/photo",
            files={"file": ("x.png", self.PNG, "image/png")},
            headers=headers,
        ).json()["hero_image"]

        assert (
            client.delete(
                f"/api/v1/guide/listings/{listing.id}", headers=headers
            ).status_code
            == 200
        )
        assert not (UPLOADS_ROOT / url.removeprefix("/uploads/")).parent.exists()
