"""Admin console endpoints: user management, guide catalog, experience and
booking administration, Supabase sync reporting, and dashboard stats."""

from collections.abc import Iterator
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.api.v1.public import MOCK_EXPERIENCES
from app.core.config import settings
from typing import Any
from sqlalchemy.orm import Session
from app.core.security import create_access_token, get_password_hash
from app.models.booking import Booking, BookingStatus
from app.models.guide import Guide
from app.models.user import User

ADMIN_API = "/api/v1/admin"


@pytest.fixture(autouse=True)
def _restore_mock_experiences() -> Iterator[None]:
    """The experience admin endpoints mutate the module-level mock list."""
    snapshot = [dict(entry) for entry in MOCK_EXPERIENCES]
    yield
    MOCK_EXPERIENCES[:] = snapshot


def _user(db: Session, email: str, role: str = "traveler", **extra: Any) -> User:
    fields = dict(
        email=email,
        firstName=email.split("@")[0].title(),
        lastName="Tester",
        hashed_password=get_password_hash("TestPassword123!"),
        role=role,
        is_active=True,
    )
    fields.update(extra)
    user = User(**fields)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _guide(db: Session, name: str = "Annapurna Tshering", **extra: Any) -> Guide:
    fields = dict(
        name=name,
        image="https://example.com/guide.jpg",
        role="Trekking guide",
        rating=4.8,
        reviews=37,
        bio="Two decades on the Annapurna circuit.",
        languages=["Nepali", "English"],
        cities=["Pokhara", "Kathmandu"],
        gallery=[],
        verified=False,
        is_active=True,
    )
    fields.update(extra)
    guide = Guide(**fields)
    db.add(guide)
    db.commit()
    db.refresh(guide)
    return guide


class TestAdminGate:
    def test_anonymous_cannot_reach_admin_routes(self, client: TestClient) -> None:
        assert client.get(f"{ADMIN_API}/users").status_code == 401

    def test_travelers_cannot_reach_admin_routes(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _user(db_session, "notadmin@example.com")
        assert (
            client.get(f"{ADMIN_API}/users", headers=_bearer(traveler)).status_code
            == 403
        )


class TestUserManagement:
    def test_list_filters_by_role(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-list@example.com", role="admin")
        _user(db_session, "trav-one@example.com")
        _user(db_session, "trav-two@example.com")
        _user(db_session, "host-one@example.com", role="host")

        response = client.get(
            f"{ADMIN_API}/users", params={"role": "traveler"}, headers=_bearer(admin)
        )
        assert response.status_code == 200, response.text
        roles = {row["role"] for row in response.json()}
        assert roles == {"traveler"}
        assert len(response.json()) >= 2

    def test_patch_updates_plain_fields(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-patch@example.com", role="admin")
        target = _user(db_session, "patch-target@example.com")

        response = client.patch(
            f"{ADMIN_API}/users/{target.id}",
            json={"firstName": "Renamed", "is_active": False},
            headers=_bearer(admin),
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"status": "ok", "user_id": target.id}
        db_session.refresh(target)
        assert target.firstName == "Renamed"
        assert target.is_active is False

    def test_patch_refuses_protected_fields(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-protect@example.com", role="admin")
        target = _user(db_session, "protect-target@example.com")
        for field in ("hashed_password", "id", "created_at"):
            response = client.patch(
                f"{ADMIN_API}/users/{target.id}",
                json={field: "x"},
                headers=_bearer(admin),
            )
            assert response.status_code == 400, response.text
            assert field in response.json()["detail"]

    def test_patch_validates_and_normalizes_roles(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-role@example.com", role="admin")
        target = _user(db_session, "role-target@example.com")

        unknown = client.patch(
            f"{ADMIN_API}/users/{target.id}",
            json={"role": "jedi"},
            headers=_bearer(admin),
        )
        assert unknown.status_code == 400

        legacy = client.patch(
            f"{ADMIN_API}/users/{target.id}",
            json={"role": "content-writer"},
            headers=_bearer(admin),
        )
        assert legacy.status_code == 200, legacy.text
        db_session.refresh(target)
        assert target.role == "content-manager"

    def test_patch_ignores_unknown_keys(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-unknown@example.com", role="admin")
        target = _user(db_session, "unknown-key@example.com")
        response = client.patch(
            f"{ADMIN_API}/users/{target.id}",
            json={"is_superuser": True},
            headers=_bearer(admin),
        )
        assert response.status_code == 200
        db_session.refresh(target)
        assert not hasattr(target, "is_superuser")

    def test_suspend_and_activate_toggle_the_flag(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-toggle@example.com", role="admin")
        target = _user(db_session, "toggle-target@example.com")

        suspended = client.post(
            f"{ADMIN_API}/users/{target.id}/suspend", headers=_bearer(admin)
        )
        assert suspended.status_code == 200
        db_session.refresh(target)
        assert target.is_active is False

        activated = client.post(
            f"{ADMIN_API}/users/{target.id}/activate", headers=_bearer(admin)
        )
        assert activated.status_code == 200
        db_session.refresh(target)
        assert target.is_active is True

    def test_delete_removes_the_user(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-delete@example.com", role="admin")
        target = _user(db_session, "delete-target@example.com")

        deleted = client.delete(
            f"{ADMIN_API}/users/{target.id}", headers=_bearer(admin)
        )
        assert deleted.status_code == 200
        assert db_session.query(User).filter(User.id == target.id).first() is None

    def test_missing_users_return_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-404@example.com", role="admin")
        headers = _bearer(admin)
        assert (
            client.patch(
                f"{ADMIN_API}/users/999999", json={"firstName": "x"}, headers=headers
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{ADMIN_API}/users/999999/suspend", headers=headers
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{ADMIN_API}/users/999999/activate", headers=headers
            ).status_code
            == 404
        )
        assert (
            client.delete(f"{ADMIN_API}/users/999999", headers=headers).status_code
            == 404
        )


class TestGuideCatalog:
    def test_list_returns_catalog_rows(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-guides@example.com", role="admin")
        _guide(db_session)
        response = client.get(f"{ADMIN_API}/guides", headers=_bearer(admin))
        assert response.status_code == 200, response.text
        rows = response.json()
        assert len(rows) == 1
        assert rows[0]["name"] == "Annapurna Tshering"
        assert rows[0]["cities"] == ["Pokhara", "Kathmandu"]
        assert rows[0]["verified"] is False

        matching = client.get(
            f"{ADMIN_API}/guides", params={"city": "Pokhara"}, headers=_bearer(admin)
        )
        assert matching.status_code == 200
        assert [row["name"] for row in matching.json()] == ["Annapurna Tshering"]

        partial = client.get(
            f"{ADMIN_API}/guides", params={"city": "Pokhar"}, headers=_bearer(admin)
        )
        assert partial.json() == []

    def test_patch_verify_suspend_and_delete(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-guidelifecycle@example.com", role="admin")
        guide = _guide(db_session)
        headers = _bearer(admin)

        patched = client.patch(
            f"{ADMIN_API}/guides/{guide.id}", json={"rating": 4.9}, headers=headers
        )
        assert patched.status_code == 200, patched.text
        db_session.refresh(guide)
        assert guide.rating == 4.9

        verified = client.post(f"{ADMIN_API}/guides/{guide.id}/verify", headers=headers)
        assert verified.status_code == 200
        db_session.refresh(guide)
        assert guide.verified is True

        suspended = client.post(
            f"{ADMIN_API}/guides/{guide.id}/suspend", headers=headers
        )
        assert suspended.status_code == 200
        db_session.refresh(guide)
        assert guide.is_active is False

        deleted = client.delete(f"{ADMIN_API}/guides/{guide.id}", headers=headers)
        assert deleted.status_code == 200
        assert db_session.query(Guide).filter(Guide.id == guide.id).first() is None

    def test_missing_guides_return_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-guides404@example.com", role="admin")
        headers = _bearer(admin)
        assert (
            client.patch(
                f"{ADMIN_API}/guides/999999", json={"rating": 1}, headers=headers
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{ADMIN_API}/guides/999999/verify", headers=headers
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{ADMIN_API}/guides/999999/suspend", headers=headers
            ).status_code
            == 404
        )
        assert (
            client.delete(f"{ADMIN_API}/guides/999999", headers=headers).status_code
            == 404
        )


class TestExperienceAdmin:
    def test_list_filters_mock_experiences_by_city(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-exp@example.com", role="admin")
        all_rows = client.get(f"{ADMIN_API}/experiences", headers=_bearer(admin))
        assert all_rows.status_code == 200, all_rows.text
        assert len(all_rows.json()) == len(MOCK_EXPERIENCES)

        first_city = MOCK_EXPERIENCES[0]["city"]
        filtered = client.get(
            f"{ADMIN_API}/experiences",
            params={"city": first_city.upper()},
            headers=_bearer(admin),
        )
        assert filtered.status_code == 200
        assert filtered.json()
        assert {row["city"] for row in filtered.json()} == {first_city}

    def test_create_update_and_delete_round_trip(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-expcrud@example.com", role="admin")
        headers = _bearer(admin)

        created = client.post(
            f"{ADMIN_API}/experiences",
            json={"title": "Test Experience", "city": "Pokhara", "price": 50},
            headers=headers,
        )
        assert created.status_code == 200, created.text
        new_id = created.json()["experience"]["id"]
        assert new_id == max(entry["id"] for entry in MOCK_EXPERIENCES)

        patched = client.patch(
            f"{ADMIN_API}/experiences/{new_id}",
            json={"price": 75},
            headers=headers,
        )
        assert patched.status_code == 200
        assert patched.json()["experience"]["price"] == 75

        deleted = client.delete(f"{ADMIN_API}/experiences/{new_id}", headers=headers)
        assert deleted.status_code == 200
        assert new_id not in {entry["id"] for entry in MOCK_EXPERIENCES}

    def test_missing_experiences_return_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-exp404@example.com", role="admin")
        headers = _bearer(admin)
        assert (
            client.patch(
                f"{ADMIN_API}/experiences/999999", json={"price": 1}, headers=headers
            ).status_code
            == 404
        )
        assert (
            client.delete(
                f"{ADMIN_API}/experiences/999999", headers=headers
            ).status_code
            == 404
        )


class TestBookingAdmin:
    def _booking(self, db: Session, user: User, **overrides: Any) -> Booking:
        fields = dict(
            user_id=user.id,
            experience_id=5,
            experience_title="Lake Day Kayak",
            city="Pokhara",
            date=datetime(2026, 12, 24),
            guests=2,
            price=180.0,
            status=BookingStatus.accepted,
        )
        fields.update(overrides)
        booking = Booking(**fields)
        db.add(booking)
        db.commit()
        db.refresh(booking)
        return booking

    def test_list_exposes_bookings_and_filters_by_status(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-bookings@example.com", role="admin")
        traveler = _user(db_session, "booking-traveler@example.com")
        booking = self._booking(db_session, traveler)
        self._booking(
            db_session, traveler, status=BookingStatus.cancelled, experience_id=6
        )
        headers = _bearer(admin)

        everything = client.get(f"{ADMIN_API}/bookings", headers=headers)
        assert everything.status_code == 200, everything.text
        assert len(everything.json()) == 2
        row = next(r for r in everything.json() if r["id"] == booking.id)
        assert row["total_price"] == 180.0
        assert row["guests"] == 2

        only_cancelled = client.get(
            f"{ADMIN_API}/bookings", params={"status": "cancelled"}, headers=headers
        )
        assert only_cancelled.status_code == 200
        assert {r["status"] for r in only_cancelled.json()} == {"cancelled"}

    def test_patch_and_cancel(self, client: TestClient, db_session: Session) -> None:
        admin = _user(db_session, "root-bookingedit@example.com", role="admin")
        traveler = _user(db_session, "bookingedit-traveler@example.com")
        booking = self._booking(db_session, traveler)
        headers = _bearer(admin)

        patched = client.patch(
            f"{ADMIN_API}/bookings/{booking.id}",
            json={"guests": 4, "bogus_field": "ignored"},
            headers=headers,
        )
        assert patched.status_code == 200, patched.text
        db_session.refresh(booking)
        assert booking.guests == 4

        cancelled = client.post(
            f"{ADMIN_API}/bookings/{booking.id}/cancel", headers=headers
        )
        assert cancelled.status_code == 200
        db_session.refresh(booking)
        assert booking.status == BookingStatus.cancelled

    def test_missing_bookings_return_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-bookings404@example.com", role="admin")
        headers = _bearer(admin)
        assert (
            client.patch(
                f"{ADMIN_API}/bookings/999999", json={"guests": 1}, headers=headers
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{ADMIN_API}/bookings/999999/cancel", headers=headers
            ).status_code
            == 404
        )


class TestSyncReporting:
    @pytest.fixture(autouse=True)
    def _unconfigured_supabase(self, monkeypatch: pytest.MonkeyPatch) -> None:
        # Deterministic: never hit a real Supabase project from tests.
        monkeypatch.setattr(settings, "SUPABASE_URL", "")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "")

    def test_sync_check_reports_unconfigured_backend(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-sync@example.com", role="admin")
        _user(db_session, "sync-target@example.com")

        response = client.get(f"{ADMIN_API}/sync/check", headers=_bearer(admin))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["total_checked"] >= 2
        assert body["out_of_sync"] == body["total_checked"]
        first = body["users"][0]
        assert first["sync_status"] == "not_synced"
        assert "not configured" in first["supabase_check"]["error"]

    def test_sync_fix_counts_and_reports_users(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-syncfix@example.com", role="admin")
        target = _user(db_session, "syncfix-target@example.com")

        scoped = client.post(
            f"{ADMIN_API}/sync/fix",
            json=[target.id],
            headers=_bearer(admin),
        )
        assert scoped.status_code == 200, scoped.text
        scoped_body = scoped.json()
        assert scoped_body["processed"] == 1
        assert scoped_body["already_synced"] == 0
        assert scoped_body["errors"][0]["user_id"] == target.id

        everyone = client.post(f"{ADMIN_API}/sync/fix", headers=_bearer(admin))
        assert everyone.status_code == 200
        assert everyone.json()["processed"] >= 2


class TestDashboardStats:
    def test_stats_count_users_guides_and_bookings(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _user(db_session, "root-stats@example.com", role="admin")
        traveler = _user(db_session, "stats-traveler@example.com")
        _guide(db_session, name="Verified Guide", verified=True, is_active=True)
        _guide(db_session, name="Retired Guide", is_active=False)
        booking_row = Booking(
            user_id=traveler.id,
            experience_id=1,
            experience_title="Stats Trip",
            city="Pokhara",
            date=datetime(2027, 1, 1),
            guests=1,
            price=10.0,
            status=BookingStatus.upcoming,
        )
        db_session.add(booking_row)
        db_session.commit()

        response = client.get(f"{ADMIN_API}/stats", headers=_bearer(admin))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["total_users"] >= 2
        assert body["total_guides"] == 2
        assert body["total_bookings"] == 1
        assert body["active_guides"] == 1
        assert body["verified_guides"] == 1
