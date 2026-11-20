"""Traveler bookings API: availability against the catalog guide, listing,
creation conflicts, and the cancel/archive lifecycle."""

from datetime import datetime

from fastapi.testclient import TestClient
from typing import Any
from sqlalchemy.orm import Session

from app.core.security import create_access_token, get_password_hash
from app.models.booking import Booking, BookingStatus
from app.models.user import User

BOOKINGS = "/api/v1/bookings"
CATALOG_GUIDE_EMAIL = "guide@guides-nepal.com"


def _register(client: TestClient, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPassword123!",
            "firstName": "Trip",
            "lastName": email.split("@")[0].title(),
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _me(client: TestClient, headers: dict) -> int:
    return int(client.get("/api/v1/profile/me", headers=headers).json()["id"])


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _catalog_guide(db: Session) -> User:
    guide = User(
        email=CATALOG_GUIDE_EMAIL,
        firstName="Booking",
        lastName="Guide",
        hashed_password=get_password_hash("TestPassword123!"),
        role="guide",
        is_active=True,
    )
    db.add(guide)
    db.commit()
    db.refresh(guide)
    return guide


def _booking(
    db: Session, user_id: int, guide_id: int | None = None, **overrides: Any
) -> Booking:
    fields = dict(
        user_id=user_id,
        guide_user_id=guide_id,
        experience_id=4,
        experience_title="Sarangkot Sunrise Hike",
        city="Pokhara",
        date=datetime(2026, 11, 5),
        guests=2,
        price=90.0,
        status=BookingStatus.accepted,
    )
    fields.update(overrides)
    booking = Booking(**fields)
    db.add(booking)
    db.commit()
    db.refresh(booking)
    return booking


class TestAuthGate:
    def test_all_booking_routes_require_a_token(self, client: TestClient) -> None:
        assert client.get(f"{BOOKINGS}/").status_code == 401
        assert (
            client.get(
                f"{BOOKINGS}/availability", params={"date": "2026-11-05"}
            ).status_code
            == 401
        )
        assert (
            client.post(
                f"{BOOKINGS}/",
                json={"experience_id": 1, "date": "2026-11-05T00:00:00"},
            ).status_code
            == 401
        )
        assert client.post(f"{BOOKINGS}/1/cancel").status_code == 401
        assert client.post(f"{BOOKINGS}/1/archive").status_code == 401


class TestAvailability:
    def test_503_without_a_catalog_guide(self, client: TestClient) -> None:
        headers = _register(client, "avail-noguide@example.com")
        response = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-11-05"},
            headers=headers,
        )
        assert response.status_code == 503
        assert "unavailable" in response.json()["detail"]

    def test_free_when_the_guide_has_nothing_booked(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _catalog_guide(db_session)
        headers = _register(client, "avail-free@example.com")
        response = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-11-05"},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"available": True, "status": "free"}
        assert guide.role == "guide"

    def test_reports_reserved_and_booked_states(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _catalog_guide(db_session)
        headers = _register(client, "avail-states@example.com")
        user_id = _me(client, headers)
        booking = _booking(db_session, user_id, guide.id, status=BookingStatus.upcoming)

        reserved = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-11-05"},
            headers=headers,
        )
        assert reserved.json() == {"available": False, "status": "reserved"}

        booking.status = BookingStatus.accepted
        db_session.commit()
        booked = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-11-05"},
            headers=headers,
        )
        assert booked.json() == {"available": False, "status": "booked"}

        # Other dates stay free.
        elsewhere = client.get(
            f"{BOOKINGS}/availability",
            params={"date": "2026-11-06"},
            headers=headers,
        )
        assert elsewhere.json() == {"available": True, "status": "free"}

    def test_date_format_is_enforced(self, client: TestClient) -> None:
        headers = _register(client, "avail-badformat@example.com")
        response = client.get(
            f"{BOOKINGS}/availability", params={"date": "tomorrow"}, headers=headers
        )
        assert response.status_code == 422


class TestListingAndCreation:
    def test_listing_is_scoped_to_the_signed_in_traveler(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _catalog_guide(db_session)
        headers_a = _register(client, "list-a@example.com")
        headers_b = _register(client, "list-b@example.com")
        _booking(db_session, _me(client, headers_a), guide.id)
        _booking(
            db_session, _me(client, headers_b), guide.id, experience_title="Other trip"
        )

        listed = client.get(f"{BOOKINGS}/", headers=headers_a)
        assert listed.status_code == 200, listed.text
        rows = listed.json()
        assert len(rows) == 1
        assert rows[0]["experience_title"] == "Sarangkot Sunrise Hike"

    def test_create_assigns_the_catalog_guide(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _catalog_guide(db_session)
        headers = _register(client, "create-booking@example.com")
        response = client.post(
            f"{BOOKINGS}/",
            json={
                "experience_id": 4,
                "experience_title": "Sarangkot Sunrise Hike",
                "city": "Pokhara",
                "date": "2026-11-07T00:00:00",
                "guests": 2,
                "price": 90.0,
            },
            headers=headers,
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["guide_user_id"] == guide.id
        assert body["guide_name"] == "Booking Guide"

    def test_creating_a_double_booking_on_the_same_date_is_409(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _catalog_guide(db_session)
        headers = _register(client, "create-conflict@example.com")
        user_id = _me(client, headers)
        _booking(db_session, user_id, guide.id)

        response = client.post(
            f"{BOOKINGS}/",
            json={
                "experience_id": 5,
                "experience_title": "Another Trip",
                "city": "Pokhara",
                "date": "2026-11-05T00:00:00",
                "guests": 1,
                "price": 45.0,
            },
            headers=headers,
        )
        assert response.status_code == 409, response.text
        assert "already" in response.json()["detail"]


class TestCancelAndArchive:
    def test_owner_can_cancel(self, client: TestClient, db_session: Session) -> None:
        headers = _register(client, "cancel-owner@example.com")
        booking = _booking(db_session, _me(client, headers))

        response = client.post(f"{BOOKINGS}/{booking.id}/cancel", headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "cancelled"
        db_session.refresh(booking)
        assert booking.status == BookingStatus.cancelled

    def test_owner_can_archive(self, client: TestClient, db_session: Session) -> None:
        headers = _register(client, "archive-owner@example.com")
        booking = _booking(db_session, _me(client, headers))

        response = client.post(f"{BOOKINGS}/{booking.id}/archive", headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "archived"
        db_session.refresh(booking)
        assert booking.status == BookingStatus.archived

    def test_foreign_and_missing_bookings_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _register(client, "own-lifecycle@example.com")
        booking = _booking(db_session, _me(client, owner))
        stranger = _register(client, "stranger-lifecycle@example.com")

        assert (
            client.post(f"{BOOKINGS}/{booking.id}/cancel", headers=stranger).status_code
            == 404
        )
        assert (
            client.post(
                f"{BOOKINGS}/{booking.id}/archive", headers=stranger
            ).status_code
            == 404
        )
        assert (
            client.post(f"{BOOKINGS}/999999/cancel", headers=owner).status_code == 404
        )
        assert (
            client.post(f"{BOOKINGS}/999999/archive", headers=owner).status_code == 404
        )
