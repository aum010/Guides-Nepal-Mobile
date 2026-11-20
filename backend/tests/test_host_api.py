"""Host dashboard endpoints: the custom host auth gate plus experience,
tour and booking management scoped to the signed-in host."""

from typing import Any
from sqlalchemy.orm import Session
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.user import User

HOST_API = "/api/v1/host"

EXPERIENCE_PAYLOAD = {
    "title": "Kathmandu Valley Heritage Walk",
    "city": "Kathmandu",
    "category": "culture",
    "description": "A half-day walk through the durbar square and old courtyards.",
    "price": 45.0,
    "duration": "4 hours",
}

TOUR_PAYLOAD = {
    "title": "Bhaktapur Pottery Workshop",
    "city": "Bhaktapur",
    "description": "Spend a morning at the potters' square with a local family.",
    "itinerary": "Meet at Taumadhi, walk to Pottery Square, hands-on session, tea.",
    "meeting_point": "Taumadhi Square",
    "duration": "3 hours",
    "difficulty": "easy",
    "max_guests": 8,
    "price": 35.0,
}


def _host(db: Session, email: str, role: str = "host", is_active: bool = True) -> User:
    user = User(
        email=email,
        firstName=email.split("@")[0].title(),
        lastName="Host",
        hashed_password=get_password_hash("TestPassword123!"),
        role=role,
        is_active=is_active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


class TestHostAuthGate:
    def test_missing_header_is_401(self, client: TestClient) -> None:
        response = client.get(f"{HOST_API}/experiences")
        assert response.status_code == 401

    def test_invalid_token_maps_to_403(self, client: TestClient) -> None:
        response = client.get(
            f"{HOST_API}/experiences",
            headers={"Authorization": "Bearer not.a.valid.token"},
        )
        assert response.status_code == 403
        assert response.json()["detail"] == "Host account required"

    def test_non_host_roles_are_403(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _host(db_session, "traveler-nothost@example.com", role="traveler")
        response = client.get(f"{HOST_API}/experiences", headers=_bearer(traveler))
        assert response.status_code == 403

    def test_inactive_hosts_are_403(
        self, client: TestClient, db_session: Session
    ) -> None:
        sleeper = _host(db_session, "sleeping-host@example.com", is_active=False)
        response = client.get(f"{HOST_API}/experiences", headers=_bearer(sleeper))
        assert response.status_code == 403


class TestHostExperiences:
    def test_create_list_update_and_delete(
        self, client: TestClient, db_session: Session
    ) -> None:
        host = _host(db_session, "exp-crud-host@example.com")
        headers = _bearer(host)

        created = client.post(
            f"{HOST_API}/experiences", json=EXPERIENCE_PAYLOAD, headers=headers
        )
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["slug"] == "kathmandu-valley-heritage-walk"
        assert body["is_active"] is True

        listed = client.get(f"{HOST_API}/experiences", headers=headers)
        assert listed.status_code == 200
        assert [row["id"] for row in listed.json()] == [body["id"]]

        patched = client.patch(
            f"{HOST_API}/experiences/{body['id']}",
            json={**EXPERIENCE_PAYLOAD, "title": "New Heritage Walk", "price": 60.0},
            headers=headers,
        )
        assert patched.status_code == 200, patched.text
        assert patched.json()["title"] == "New Heritage Walk"
        assert patched.json()["slug"] == "new-heritage-walk"

        deleted = client.delete(f"{HOST_API}/experiences/{body['id']}", headers=headers)
        assert deleted.status_code == 200
        assert deleted.json() == {"status": "ok"}
        assert client.get(f"{HOST_API}/experiences", headers=headers).json() == []

    def test_duplicate_titles_conflict(
        self, client: TestClient, db_session: Session
    ) -> None:
        host = _host(db_session, "exp-dup-host@example.com")
        headers = _bearer(host)
        first = client.post(
            f"{HOST_API}/experiences", json=EXPERIENCE_PAYLOAD, headers=headers
        )
        assert first.status_code == 201

        duplicate = client.post(
            f"{HOST_API}/experiences", json=EXPERIENCE_PAYLOAD, headers=headers
        )
        assert duplicate.status_code == 409

        # Renaming another experience onto the same slug also conflicts.
        other = client.post(
            f"{HOST_API}/experiences",
            json={**EXPERIENCE_PAYLOAD, "title": "A Different Experience"},
            headers=headers,
        )
        assert other.status_code == 201
        clashing = client.patch(
            f"{HOST_API}/experiences/{other.json()['id']}",
            json=EXPERIENCE_PAYLOAD,
            headers=headers,
        )
        assert clashing.status_code == 409

    def test_experiences_are_scoped_to_their_host(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _host(db_session, "exp-owner-host@example.com")
        intruder = _host(db_session, "exp-intruder-host@example.com")
        created = client.post(
            f"{HOST_API}/experiences",
            json=EXPERIENCE_PAYLOAD,
            headers=_bearer(owner),
        )
        experience_id = created.json()["id"]

        assert (
            client.get(f"{HOST_API}/experiences", headers=_bearer(intruder)).json()
            == []
        )
        patched = client.patch(
            f"{HOST_API}/experiences/{experience_id}",
            json={**EXPERIENCE_PAYLOAD, "title": "Stolen Title"},
            headers=_bearer(intruder),
        )
        assert patched.status_code == 404
        deleted = client.delete(
            f"{HOST_API}/experiences/{experience_id}", headers=_bearer(intruder)
        )
        assert deleted.status_code == 404

    def test_schema_validation_rejects_short_input(
        self, client: TestClient, db_session: Session
    ) -> None:
        host = _host(db_session, "exp-validation-host@example.com")
        response = client.post(
            f"{HOST_API}/experiences",
            json={**EXPERIENCE_PAYLOAD, "description": "too short"},
            headers=_bearer(host),
        )
        assert response.status_code == 422


class TestHostTours:
    def test_create_list_update_and_delete(
        self, client: TestClient, db_session: Session
    ) -> None:
        host = _host(db_session, "tour-crud-host@example.com")
        headers = _bearer(host)

        created = client.post(f"{HOST_API}/tours", json=TOUR_PAYLOAD, headers=headers)
        assert created.status_code == 201, created.text
        tour_id = created.json()["id"]

        listed = client.get(f"{HOST_API}/tours", headers=headers)
        assert listed.status_code == 200
        assert [row["id"] for row in listed.json()] == [tour_id]

        patched = client.patch(
            f"{HOST_API}/tours/{tour_id}",
            json={**TOUR_PAYLOAD, "price": 40.0},
            headers=headers,
        )
        assert patched.status_code == 200
        assert patched.json()["price"] == 40.0

        deleted = client.delete(f"{HOST_API}/tours/{tour_id}", headers=headers)
        assert deleted.status_code == 200
        assert client.get(f"{HOST_API}/tours", headers=headers).json() == []

    def test_foreign_and_missing_tours_return_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _host(db_session, "tour-owner-host@example.com")
        intruder = _host(db_session, "tour-intruder-host@example.com")
        created = client.post(
            f"{HOST_API}/tours", json=TOUR_PAYLOAD, headers=_bearer(owner)
        )
        tour_id = created.json()["id"]

        foreign = client.patch(
            f"{HOST_API}/tours/{tour_id}",
            json={**TOUR_PAYLOAD, "price": 1.0},
            headers=_bearer(intruder),
        )
        assert foreign.status_code == 404
        assert (
            client.delete(
                f"{HOST_API}/tours/{tour_id}", headers=_bearer(intruder)
            ).status_code
            == 404
        )
        assert (
            client.delete(
                f"{HOST_API}/tours/999999", headers=_bearer(owner)
            ).status_code
            == 404
        )
        assert (
            client.patch(
                f"{HOST_API}/tours/999999", json=TOUR_PAYLOAD, headers=_bearer(owner)
            ).status_code
            == 404
        )


class TestHostBookings:
    def _experience(self, client: TestClient, host: Any, **overrides: Any) -> int:
        payload = {**EXPERIENCE_PAYLOAD, **overrides}
        created = client.post(
            f"{HOST_API}/experiences", json=payload, headers=_bearer(host)
        )
        assert created.status_code == 201, created.text
        return int(created.json()["id"])

    def test_booking_lifecycle(self, client: TestClient, db_session: Session) -> None:
        host = _host(db_session, "booking-host@example.com")
        headers = _bearer(host)
        experience_id = self._experience(client, host)

        created = client.post(
            f"{HOST_API}/bookings",
            json={
                "experience_id": experience_id,
                "guest_name": "Maya Gurung",
                "guest_email": "maya@example.com",
                "date": "2026-11-20T09:00:00",
                "guests": 3,
            },
            headers=headers,
        )
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["experience_title"] == "Kathmandu Valley Heritage Walk"
        assert body["total_price"] == 135.0  # 45.0 * 3 guests
        assert body["status"] == "upcoming"

        listed = client.get(f"{HOST_API}/bookings", headers=headers)
        assert listed.status_code == 200
        assert [row["id"] for row in listed.json()] == [body["id"]]

        accepted = client.patch(
            f"{HOST_API}/bookings/{body['id']}",
            json={"status": "accepted"},
            headers=headers,
        )
        assert accepted.status_code == 200, accepted.text
        assert accepted.json() == {"status": "accepted"}

    def test_invalid_decision_status_is_422(
        self, client: TestClient, db_session: Session
    ) -> None:
        host = _host(db_session, "booking-badstatus@example.com")
        response = client.patch(
            f"{HOST_API}/bookings/1",
            json={"status": "cancelled"},
            headers=_bearer(host),
        )
        assert response.status_code == 422

    def test_missing_or_foreign_booking_is_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _host(db_session, "booking-owner-host@example.com")
        intruder = _host(db_session, "booking-intruder-host@example.com")
        experience_id = self._experience(client, owner)
        created = client.post(
            f"{HOST_API}/bookings",
            json={
                "experience_id": experience_id,
                "guest_name": "Dipak Rai",
                "guest_email": "dipak@example.com",
                "date": "2026-11-21T09:00:00",
                "guests": 1,
            },
            headers=_bearer(owner),
        )
        assert created.status_code == 201

        foreign = client.patch(
            f"{HOST_API}/bookings/{created.json()['id']}",
            json={"status": "rejected"},
            headers=_bearer(intruder),
        )
        assert foreign.status_code == 404
        missing = client.patch(
            f"{HOST_API}/bookings/999999",
            json={"status": "accepted"},
            headers=_bearer(owner),
        )
        assert missing.status_code == 404

    def test_booking_needs_an_active_experience_owned_by_the_host(
        self, client: TestClient, db_session: Session
    ) -> None:
        owner = _host(db_session, "booking-paused-host@example.com")
        other = _host(db_session, "booking-other-host@example.com")
        paused_id = self._experience(client, owner)
        from app.models.booking import HostExperience

        paused_row = (
            db_session.query(HostExperience)
            .filter(HostExperience.id == paused_id)
            .one()
        )
        paused_row.is_active = False
        db_session.commit()
        foreign_id = self._experience(client, other)

        base = {
            "guest_name": "Sara Lama",
            "guest_email": "sara@example.com",
            "date": "2026-11-22T09:00:00",
            "guests": 2,
        }
        paused = client.post(
            f"{HOST_API}/bookings",
            json={"experience_id": paused_id, **base},
            headers=_bearer(owner),
        )
        assert paused.status_code == 404
        foreign = client.post(
            f"{HOST_API}/bookings",
            json={"experience_id": foreign_id, **base},
            headers=_bearer(owner),
        )
        assert foreign.status_code == 404
