"""Guide console endpoints: profile, bookings, dashboard, listings, status.

`guide` cannot self-register, so the fixtures mint the account directly and
mint its JWT with `create_access_token` — the same token the login endpoint
would issue.
"""

from datetime import datetime
from sqlalchemy.orm import Session
from typing import Any

from fastapi.testclient import TestClient

from app.core.roles import GUIDE_CAPABILITIES, role_rank
from app.core.security import create_access_token, get_password_hash
from app.models.booking import Booking, BookingStatus
from app.models.user import User

GUIDE_API = "/api/v1/guide"

LISTING_PAYLOAD = {
    "title": "Poon Hill Sunrise Trek",
    "category": "trekking",
    "city": "Pokhara",
    "area": "Annapurna",
    "description": "A gentle ridge walk to the Poon Hill viewpoint for sunrise.",
    "duration": "2 days",
    "difficulty": "easy",
    "price": 120.0,
    "max_guests": 10,
}


def _make_guide(db: Session, email: str) -> User:
    guide = User(
        email=email,
        firstName="Mingma",
        lastName="Guide",
        hashed_password=get_password_hash("TestPassword123!"),
        role="guide",
        is_active=True,
    )
    db.add(guide)
    db.commit()
    db.refresh(guide)
    return guide


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _assign_booking(
    db: Session, traveler: User, guide: User, **overrides: Any
) -> Booking:
    fields = dict(
        user_id=traveler.id,
        guide_user_id=guide.id,
        experience_id=3,
        experience_title="Poon Hill Sunrise Trek",
        city="Pokhara",
        date=datetime(2026, 12, 1),
        guests=3,
        price=360.0,
        status=BookingStatus.accepted,
    )
    fields.update(overrides)
    booking = Booking(**fields)
    db.add(booking)
    db.commit()
    db.refresh(booking)
    return booking


class TestGuideProfile:
    def test_guide_reads_its_own_profile_with_capabilities(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "me-guide@example.com")
        response = client.get(f"{GUIDE_API}/me", headers=_bearer(guide))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["email"] == "me-guide@example.com"
        assert body["role"] == "guide"
        assert body["rank"] == role_rank("guide")
        assert body["capabilities"] == sorted(GUIDE_CAPABILITIES)

    def test_travelers_are_rejected(self, client: TestClient) -> None:
        registered = client.post(
            "/api/v1/auth/register",
            json={
                "email": "traveler-noguide@example.com",
                "password": "TestPassword123!",
                "firstName": "Ann",
                "lastName": "Traveler",
            },
        )
        assert registered.status_code == 200, registered.text
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
        assert client.get(f"{GUIDE_API}/me", headers=headers).status_code == 403

    def test_anonymous_is_rejected(self, client: TestClient) -> None:
        assert client.get(f"{GUIDE_API}/me").status_code == 401


class TestGuideBookings:
    def test_lists_only_bookings_assigned_to_this_guide(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "bookings-guide@example.com")
        traveler = User(
            email="bookings-traveler@example.com",
            firstName="Sita",
            lastName="Trekker",
            hashed_password=get_password_hash("TestPassword123!"),
            role="traveler",
            is_active=True,
        )
        db_session.add(traveler)
        db_session.commit()
        assigned = _assign_booking(db_session, traveler, guide)
        # A booking assigned to someone else must not appear.
        second = _assign_booking(db_session, traveler, guide, experience_id=4)

        response = client.get(f"{GUIDE_API}/bookings", headers=_bearer(guide))
        assert response.status_code == 200, response.text
        rows = response.json()
        assert {row["id"] for row in rows} == {assigned.id, second.id}
        assert rows[0]["traveler_name"] == "Sita Trekker"
        assert rows[0]["traveler_email"] == "bookings-traveler@example.com"
        assert rows[0]["status"] == "accepted"

    def test_decide_accepts_a_valid_status(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "decide-guide@example.com")
        traveler = User(
            email="decide-traveler@example.com",
            firstName="Ram",
            lastName="Porter",
            hashed_password=get_password_hash("TestPassword123!"),
            role="traveler",
            is_active=True,
        )
        db_session.add(traveler)
        db_session.commit()
        booking = _assign_booking(db_session, traveler, guide)

        response = client.patch(
            f"{GUIDE_API}/bookings/{booking.id}",
            json={"status": "completed"},
            headers=_bearer(guide),
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"id": booking.id, "status": "completed"}

    def test_decide_rejects_an_unknown_status(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "decide-badstatus@example.com")
        response = client.patch(
            f"{GUIDE_API}/bookings/1",
            json={"status": "exploded"},
            headers=_bearer(guide),
        )
        assert response.status_code == 422

    def test_decide_404s_for_bookings_not_assigned_to_this_guide(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "decide-foreign@example.com")
        other_guide = _make_guide(db_session, "decide-other@example.com")
        traveler = User(
            email="decide-foreign-traveler@example.com",
            firstName="Uma",
            lastName="Walker",
            hashed_password=get_password_hash("TestPassword123!"),
            role="traveler",
            is_active=True,
        )
        db_session.add(traveler)
        db_session.commit()
        booking = _assign_booking(db_session, traveler, other_guide)

        response = client.patch(
            f"{GUIDE_API}/bookings/{booking.id}",
            json={"status": "rejected"},
            headers=_bearer(guide),
        )
        assert response.status_code == 404


class TestGuideListings:
    def _create_listing(self, client: TestClient, guide: Any, **overrides: Any) -> Any:
        payload = {**LISTING_PAYLOAD, **overrides}
        response = client.post(
            f"{GUIDE_API}/listings", json=payload, headers=_bearer(guide)
        )
        assert response.status_code == 201, response.text
        return response.json()

    def test_create_returns_computed_fields(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "listing-create@example.com")
        body = self._create_listing(client, guide)
        assert body["id"] > 0
        assert body["booked_guests"] == 0
        assert body["available_spots"] == 10
        assert body["occupancy_pct"] == 0

    def test_listing_payload_validation(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "listing-invalid@example.com")
        response = client.post(
            f"{GUIDE_API}/listings",
            json={**LISTING_PAYLOAD, "max_guests": 0},
            headers=_bearer(guide),
        )
        assert response.status_code == 422

    def test_update_changes_fields_and_guards_capacity(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "listing-update@example.com")
        listing = self._create_listing(client, guide)

        patched = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}",
            json={"price": 150.0, "title": "Poon Hill Express"},
            headers=_bearer(guide),
        )
        assert patched.status_code == 200, patched.text
        assert patched.json()["price"] == 150.0
        assert patched.json()["title"] == "Poon Hill Express"

        # Book three guests, then try to shrink below the booked count.
        cap = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}/capacity",
            json={"booked_delta": 3},
            headers=_bearer(guide),
        )
        assert cap.status_code == 200, cap.text
        assert cap.json()["booked_guests"] == 3

        shrink = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}",
            json={"max_guests": 2},
            headers=_bearer(guide),
        )
        assert shrink.status_code == 422

    def test_capacity_absolute_and_delta_bounds(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "listing-capacity@example.com")
        listing = self._create_listing(client, guide)

        raised = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}/capacity",
            json={"max_guests": 25},
            headers=_bearer(guide),
        )
        assert raised.status_code == 200
        assert raised.json()["max_guests"] == 25

        negative = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}/capacity",
            json={"booked_delta": -1},
            headers=_bearer(guide),
        )
        assert negative.status_code == 422

    def test_foreign_listings_are_invisible_to_crud(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _make_guide(db_session, "listing-owner@example.com")
        intruder = _make_guide(db_session, "listing-intruder@example.com")
        listing = self._create_listing(client, owner)

        patched = client.patch(
            f"{GUIDE_API}/listings/{listing['id']}",
            json={"price": 1.0},
            headers=_bearer(intruder),
        )
        assert patched.status_code == 404
        deleted = client.delete(
            f"{GUIDE_API}/listings/{listing['id']}", headers=_bearer(intruder)
        )
        assert deleted.status_code == 404

    def test_delete_removes_the_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "listing-delete@example.com")
        listing = self._create_listing(client, guide)

        deleted = client.delete(
            f"{GUIDE_API}/listings/{listing['id']}", headers=_bearer(guide)
        )
        assert deleted.status_code == 200
        assert deleted.json() == {"status": "ok"}

        listed = client.get(f"{GUIDE_API}/listings", headers=_bearer(guide))
        assert listed.json() == []

        again = client.delete(
            f"{GUIDE_API}/listings/{listing['id']}", headers=_bearer(guide)
        )
        assert again.status_code == 404


class TestGuideStatusUpdates:
    def test_post_list_and_delete_status_updates(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "status-guide@example.com")
        headers = _bearer(guide)

        created = client.post(
            f"{GUIDE_API}/status",
            json={"message": "Trail to Sarangkot is clear.", "area": "Pokhara"},
            headers=headers,
        )
        assert created.status_code == 201, created.text
        status_id = created.json()["id"]
        assert created.json()["message"] == "Trail to Sarangkot is clear."

        listed = client.get(f"{GUIDE_API}/status", headers=headers)
        assert listed.status_code == 200
        assert [row["id"] for row in listed.json()] == [status_id]

        deleted = client.delete(f"{GUIDE_API}/status/{status_id}", headers=headers)
        assert deleted.status_code == 200
        assert client.get(f"{GUIDE_API}/status", headers=headers).json() == []

        missing = client.delete(f"{GUIDE_API}/status/{status_id}", headers=headers)
        assert missing.status_code == 404

    def test_post_can_attach_to_an_owned_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "status-listing@example.com")
        headers = _bearer(guide)
        listing = client.post(
            f"{GUIDE_API}/listings", json=LISTING_PAYLOAD, headers=headers
        )
        assert listing.status_code == 201, listing.text

        created = client.post(
            f"{GUIDE_API}/status",
            json={
                "update_type": "capacity",
                "message": "Two spots left on Poon Hill.",
                "listing_id": listing.json()["id"],
            },
            headers=headers,
        )
        assert created.status_code == 201, created.text
        assert created.json()["listing_id"] == listing.json()["id"]

    def test_post_rejects_a_foreign_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _make_guide(db_session, "status-owner@example.com")
        other = _make_guide(db_session, "status-other@example.com")
        listing = client.post(
            f"{GUIDE_API}/listings", json=LISTING_PAYLOAD, headers=_bearer(owner)
        )
        assert listing.status_code == 201

        response = client.post(
            f"{GUIDE_API}/status",
            json={
                "message": "Taking over this listing.",
                "listing_id": listing.json()["id"],
            },
            headers=_bearer(other),
        )
        assert response.status_code == 404

    def test_limit_bounds_are_enforced(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "status-limit@example.com")
        response = client.get(
            f"{GUIDE_API}/status", params={"limit": 0}, headers=_bearer(guide)
        )
        assert response.status_code == 422


class TestGuideOnboarding:
    def test_get_before_save_reports_incomplete(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "onboarding-fresh@example.com")
        response = client.get(f"{GUIDE_API}/onboarding", headers=_bearer(guide))
        assert response.status_code == 200
        assert response.json() == {"onboarding": None, "completed": False}

    def test_onboarding_round_trips_and_updates(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "onboarding-round@example.com")
        headers = _bearer(guide)
        payload = {
            "display_name": "Dawa Sherpa",
            "expertise_areas": ["trekking"],
            "cities": ["Pokhara", "Besisahar"],
            "languages": ["Nepali", "English"],
            "bio": "Local guide with a decade on the Annapurna trails.",
            "years_experience": "10",
            "default_max_guests": 12,
            "onboarding_completed": True,
        }

        saved = client.put(f"{GUIDE_API}/onboarding", json=payload, headers=headers)
        assert saved.status_code == 200, saved.text
        body = saved.json()["onboarding"]
        assert body["display_name"] == "Dawa Sherpa"
        assert body["guide_user_id"] == guide.id
        assert body["cities"] == ["Pokhara", "Besisahar"]

        fetched = client.get(f"{GUIDE_API}/onboarding", headers=headers)
        assert fetched.json()["completed"] is True
        assert fetched.json()["onboarding"]["display_name"] == "Dawa Sherpa"

        # A second PUT takes the update path for the existing profile.
        renamed = client.put(
            f"{GUIDE_API}/onboarding",
            json={**payload, "display_name": "Dawa 'Kelbu' Sherpa"},
            headers=headers,
        )
        assert renamed.status_code == 200
        assert renamed.json()["onboarding"]["display_name"] == "Dawa 'Kelbu' Sherpa"


class TestGuideDashboard:
    def test_empty_dashboard_reports_zeroes(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "dashboard-empty@example.com")
        response = client.get(f"{GUIDE_API}/dashboard", headers=_bearer(guide))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["guide"]["email"] == "dashboard-empty@example.com"
        assert body["stats"] == {
            "listings": 0,
            "upcoming_bookings": 0,
            "total_guests": 0,
            "total_capacity": 0,
            "booked_capacity": 0,
            "available_spots": 0,
        }
        assert body["listings"] == []
        assert body["recent_status"] == []

    def test_dashboard_aggregates_listings_and_bookings(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_guide(db_session, "dashboard-full@example.com")
        headers = _bearer(guide)
        traveler = User(
            email="dashboard-traveler@example.com",
            firstName="Pemba",
            lastName="Sherpa",
            hashed_password=get_password_hash("TestPassword123!"),
            role="traveler",
            is_active=True,
        )
        db_session.add(traveler)
        db_session.commit()
        _assign_booking(db_session, traveler, guide, guests=3)

        listing = client.post(
            f"{GUIDE_API}/listings", json=LISTING_PAYLOAD, headers=headers
        )
        assert listing.status_code == 201
        client.patch(
            f"{GUIDE_API}/listings/{listing.json()['id']}/capacity",
            json={"booked_delta": 4},
            headers=headers,
        )

        response = client.get(f"{GUIDE_API}/dashboard", headers=headers)
        assert response.status_code == 200, response.text
        stats = response.json()["stats"]
        assert stats["listings"] == 1
        assert stats["upcoming_bookings"] == 1
        assert stats["total_guests"] == 3
        assert stats["total_capacity"] == 10
        assert stats["booked_capacity"] == 4
        assert stats["available_spots"] == 6
        assert len(response.json()["listings"]) == 1
