"""Unit-level coverage for `AuthService`.

The Supabase-facing methods are exercised with a faked `httpx` client so
every branch (unconfigured, found, missing, HTTP error, transport error)
runs deterministically without touching a network. The rest covers the
registration guards, the host-approval login gate, social upserts and
password updates.
"""

import httpx
from sqlalchemy.orm import Session
import pytest
from typing import Any

from app.core.config import settings
from app.core.security import verify_password
from app.models.host_application import HostApplication
from app.models.user import User
from app.schemas.auth import PrivilegedUserCreate, UserCreate
from app.services.auth_service import AuthService

FAKE_URL = "https://project.supabase.co"
FAKE_KEY = "service-role-key"


def _user(
    db: Session, email: str, role: str = "traveler", is_active: bool = True
) -> User:
    user = User(
        email=email,
        firstName="Auth",
        lastName="Subject",
        hashed_password="placeholder",
        role=role,
        is_active=is_active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


class _FakeResponse:
    def __init__(self, status_code: int, payload: Any = None, text: str = "") -> None:
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self) -> Any:
        return self._payload


class TestSupabaseSyncBranches:
    @pytest.fixture(autouse=True)
    def _configured(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", FAKE_URL)
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", FAKE_KEY)

    def test_check_returns_early_when_unconfigured(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "")
        result = AuthService(db_session).check_supabase_user_exists("a@example.com")
        assert result["exists"] is False
        assert "not configured" in result["error"]

    def test_check_reports_an_existing_user(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        seen: dict[str, Any] = {}

        def fake_get(
            url: Any, params: Any = None, headers: Any = None, timeout: Any = None
        ) -> Any:
            seen.update(url=url, params=params, headers=headers, timeout=timeout)
            return _FakeResponse(
                200,
                {
                    "users": [
                        {"id": "uuid-1", "email_confirmed_at": "2026-01-01T00:00:00"}
                    ]
                },
            )

        monkeypatch.setattr(httpx, "get", fake_get)
        result = AuthService(db_session).check_supabase_user_exists("found@example.com")
        assert result["exists"] is True
        assert result["user_id"] == "uuid-1"
        assert result["email_confirmed"] is True
        assert seen["url"] == f"{FAKE_URL}/auth/v1/admin/users"
        assert seen["params"] == {"email": "found@example.com"}
        assert seen["headers"]["apikey"] == FAKE_KEY

    def test_check_with_no_matching_users_stays_unsynced(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(
            httpx, "get", lambda *args, **kwargs: _FakeResponse(200, {"users": []})
        )
        result = AuthService(db_session).check_supabase_user_exists(
            "nobody@example.com"
        )
        assert result["exists"] is False
        assert "error" not in result

    def test_check_records_a_non_200_response(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(
            httpx, "get", lambda *args, **kwargs: _FakeResponse(500, text="boom")
        )
        result = AuthService(db_session).check_supabase_user_exists("x@example.com")
        assert result["exists"] is False
        assert "500" in result["error"]

    def test_check_records_transport_failures(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        def exploding_get(*args: Any, **kwargs: Any) -> Any:
            raise httpx.ConnectError("connection refused")

        monkeypatch.setattr(httpx, "get", exploding_get)
        result = AuthService(db_session).check_supabase_user_exists("x@example.com")
        assert result["exists"] is False
        assert "connection refused" in result["error"]

    def test_create_user_posts_when_unconfigured_is_skipped(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "")
        posted: list[Any] = []

        def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
            posted.append(args)
            return _FakeResponse(201)

        monkeypatch.setattr(httpx, "post", fake_post)
        AuthService(db_session)._create_supabase_user("skip@example.com", "pw")
        assert posted == []

    def test_create_user_posts_a_new_supabase_identity(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        calls: dict[str, Any] = {}

        def fake_post(
            url: Any, headers: Any = None, json: Any = None, timeout: Any = None
        ) -> Any:
            calls.update(url=url, headers=headers, json=json, timeout=timeout)
            return _FakeResponse(201)

        monkeypatch.setattr(httpx, "post", fake_post)
        AuthService(db_session)._create_supabase_user("new@example.com", "Secret1!")
        assert calls["url"] == f"{FAKE_URL}/auth/v1/admin/users"
        assert calls["json"] == {
            "email": "new@example.com",
            "password": "Secret1!",
            "email_confirm": True,
        }

    def test_create_user_tolerates_an_existing_identity(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        posted: list[Any] = []

        def fake_post(*args: Any, **kwargs: Any) -> Any:
            posted.append(args)
            return _FakeResponse(201)

        monkeypatch.setattr(httpx, "post", fake_post)
        AuthService(db_session)._create_supabase_user("dupe@example.com", "Secret1!")

    def test_create_user_records_server_errors(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(
            httpx, "post", lambda *a, **k: _FakeResponse(403, text="forbidden")
        )
        AuthService(db_session)._create_supabase_user("denied@example.com", "Secret1!")

    def test_create_user_survives_transport_failures(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        def exploding_post(*args: Any, **kwargs: Any) -> Any:
            raise httpx.ConnectError("network down")

        monkeypatch.setattr(httpx, "post", exploding_post)
        AuthService(db_session)._create_supabase_user("offline@example.com", "Secret1!")

    def test_ensure_creates_the_user_when_missing(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        posted = {}

        def fake_post(
            url: Any, headers: Any = None, json: Any = None, timeout: Any = None
        ) -> Any:
            posted["json"] = json
            return _FakeResponse(201)

        monkeypatch.setattr(
            httpx, "get", lambda *a, **k: _FakeResponse(200, {"users": []})
        )
        monkeypatch.setattr(httpx, "post", fake_post)
        AuthService(db_session).ensure_supabase_user("legacy@example.com", "Secret1!")
        assert posted["json"]["email"] == "legacy@example.com"

    def test_ensure_is_a_noop_when_the_user_exists(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        posted: list[Any] = []

        def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
            return _FakeResponse(
                200, {"users": [{"id": "uuid-9", "email_confirmed_at": "x"}]}
            )

        def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
            posted.append(args)
            return _FakeResponse(201)

        monkeypatch.setattr(httpx, "get", fake_get)
        monkeypatch.setattr(httpx, "post", fake_post)
        AuthService(db_session).ensure_supabase_user("exists@example.com", "Secret1!")
        assert posted == []

    def test_ensure_is_skipped_when_unconfigured(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "")
        called: list[Any] = []

        def fake_get(*args: Any, **kwargs: Any) -> None:
            called.append(args)

        monkeypatch.setattr(httpx, "get", fake_get)
        AuthService(db_session).ensure_supabase_user("nobody@example.com", "pw")
        assert called == []

    def test_ensure_survives_transport_failures(
        self, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        def exploding_get(*args: Any, **kwargs: Any) -> Any:
            raise httpx.ConnectError("network down")

        monkeypatch.setattr(httpx, "get", exploding_get)
        AuthService(db_session).ensure_supabase_user("offline@example.com", "pw")


class TestRegistrationGuards:
    @pytest.fixture(autouse=True)
    def _unconfigured(self, monkeypatch: pytest.MonkeyPatch) -> None:
        # Registration pings Supabase too; keep tests hermetic.
        monkeypatch.setattr(settings, "SUPABASE_URL", "")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "")

    def _payload(self, **overrides: Any) -> UserCreate:
        fields = dict(
            email="newcomer@example.com",
            password="StrongPass1!",
            firstName="New",
            lastName="Comer",
        )
        fields.update(overrides)
        return UserCreate(**fields)

    def test_duplicate_registration_is_refused(self, db_session: Session) -> None:
        service = AuthService(db_session)
        service.register_user(self._payload())
        with pytest.raises(Exception, match="already registered"):
            service.register_user(self._payload())

    def test_weak_password_is_refused(self, db_session: Session) -> None:
        with pytest.raises(Exception):
            AuthService(db_session).register_user(self._payload(password="weak"))

    def test_unknown_role_is_refused_even_from_a_privileged_schema(
        self, db_session: Session
    ) -> None:
        payload = PrivilegedUserCreate(
            email="wizard@example.com",
            password="StrongPass1!",
            firstName="Wiz",
            lastName="Ard",
            role="wizard",
        )
        with pytest.raises(Exception, match="not a known role"):
            AuthService(db_session).register_user(payload)

    def test_successful_registration_hashes_the_password(
        self, db_session: Session
    ) -> None:
        user = AuthService(db_session).register_user(self._payload())
        assert user.role == "traveler"
        assert user.hashed_password != "StrongPass1!"
        assert verify_password("StrongPass1!", user.hashed_password)
        assert AuthService(db_session).get_user_by_email("newcomer@example.com") == user


class TestHostApprovalLoginGate:
    def _host(self, db: Session, email: str) -> User:
        from app.core.security import get_password_hash

        user = User(
            email=email,
            firstName="Hopeful",
            lastName="Host",
            hashed_password=get_password_hash("StrongPass1!"),
            role="host",
            is_active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        return user

    def _application(self, db: Session, email: str, status: str) -> None:
        db.add(
            HostApplication(
                host_name="Hopeful Host",
                email=email,
                city="Pokhara",
                region="Gandaki",
                experience="Homestays",
                status=status,
            )
        )
        db.commit()

    def test_host_without_an_application_cannot_sign_in(
        self, db_session: Session
    ) -> None:
        self._host(db_session, "unapproved-host@example.com")
        result = AuthService(db_session).authenticate_user(
            "unapproved-host@example.com", "StrongPass1!"
        )
        assert result is None

    def test_host_with_a_pending_application_cannot_sign_in(
        self, db_session: Session
    ) -> None:
        self._host(db_session, "pending-host@example.com")
        self._application(db_session, "pending-host@example.com", "pending")
        result = AuthService(db_session).authenticate_user(
            "pending-host@example.com", "StrongPass1!"
        )
        assert result is None

    def test_host_with_an_approved_application_signs_in(
        self, db_session: Session
    ) -> None:
        host = self._host(db_session, "approved-host@example.com")
        self._application(db_session, "approved-host@example.com", "approved")
        result = AuthService(db_session).authenticate_user(
            "approved-host@example.com", "StrongPass1!"
        )
        assert result is not None
        assert result.id == host.id

    def test_unknown_inactive_and_wrong_password_all_return_none(
        self, db_session: Session
    ) -> None:
        service = AuthService(db_session)
        assert service.authenticate_user("ghost@example.com", "StrongPass1!") is None

        self._host(db_session, "sleeper@example.com")
        db_session.query(User).filter(User.email == "sleeper@example.com").update(
            {"is_active": False}
        )
        db_session.commit()
        assert service.authenticate_user("sleeper@example.com", "StrongPass1!") is None

        self._host(db_session, "wrongpw@example.com")
        assert service.authenticate_user("wrongpw@example.com", "Nope1!") is None


class TestSocialUpsertAndPasswords:
    def test_upsert_creates_then_backfills_names(self, db_session: Session) -> None:
        service = AuthService(db_session)
        created = service.upsert_social_user(
            "social@example.com", first_name="Social", last_name="User"
        )
        assert created.role == "traveler"
        assert created.firstName == "Social"

        # A later login with a name only fills gaps; it never overwrites.
        updated = service.upsert_social_user(
            "social@example.com", first_name="Ignored", last_name=None
        )
        assert updated.id == created.id
        assert updated.firstName == "Social"
        assert updated.lastName == "User"

    def test_upsert_backfills_previously_empty_names(self, db_session: Session) -> None:
        service = AuthService(db_session)
        created = service.upsert_social_user("nameless@example.com")
        assert created.firstName == ""

        updated = service.upsert_social_user(
            "nameless@example.com", first_name="Filled", last_name="In"
        )
        assert updated.firstName == "Filled"
        assert updated.lastName == "In"

    def test_password_update_rejects_weak_passwords(self, db_session: Session) -> None:
        from app.core.security import get_password_hash

        user = _user(db_session, "changepw@example.com")
        user.hashed_password = get_password_hash("StrongPass1!")
        db_session.commit()

        with pytest.raises(ValueError):
            AuthService(db_session).update_user_password(user, "weak")

    def test_password_update_round_trips(self, db_session: Session) -> None:
        from app.core.security import get_password_hash

        user = _user(db_session, "changepw2@example.com")
        user.hashed_password = get_password_hash("StrongPass1!")
        db_session.commit()

        AuthService(db_session).update_user_password(user, "BrandNewPass2!")
        assert not verify_password("StrongPass1!", user.hashed_password)
        assert verify_password("BrandNewPass2!", user.hashed_password)
