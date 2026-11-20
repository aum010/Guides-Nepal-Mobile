"""Endpoint-level coverage for the auth router.

Complements ``test_auth_service`` (which unit-tests the service): these tests
drive the HTTP surface — registration, dev seeding, the host login gate,
refresh/logout, password changes and resets, and both OAuth providers — with
every outbound call faked.
"""

from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.user import User
from app.services.auth_service import AuthService

AUTH = "/api/v1/auth"
PASSWORD = "TestPassword123!"
NEW_PASSWORD = "BrandNewPass9!"


def _payload(email: str, **overrides: Any) -> dict[str, Any]:
    return {
        "email": email,
        "password": PASSWORD,
        "firstName": "Test",
        "lastName": "User",
        **overrides,
    }


def _register(client: TestClient, email: str, **overrides: Any) -> dict[str, Any]:
    response = client.post(f"{AUTH}/register", json=_payload(email, **overrides))
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def _bearer(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _make_user(
    db: Session,
    email: str,
    role: str = "traveler",
    is_active: bool = True,
    password: str = PASSWORD,
) -> User:
    user = User(
        email=email,
        firstName="Auth",
        lastName="Subject",
        hashed_password=get_password_hash(password),
        role=role,
        is_active=is_active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


class _FakeResponse:
    def __init__(
        self, status_code: int = 200, payload: Any = None, text: str = ""
    ) -> None:
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self) -> Any:
        return self._payload


class _FakeAsyncClient:
    """Routes faked async responses by URL substring."""

    def __init__(self, routes: dict[str, Any]) -> None:
        self._routes = routes
        self.calls: list[tuple[str, str]] = []

    async def __aenter__(self) -> "_FakeAsyncClient":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None

    def _resolve(self, method: str, url: str) -> Any:
        self.calls.append((method, url))
        for fragment, response in self._routes.items():
            if fragment in url:
                if isinstance(response, Exception):
                    raise response
                return response
        return _FakeResponse(404)

    async def post(self, url: str, **kwargs: Any) -> Any:
        return self._resolve("POST", url)

    async def get(self, url: str, **kwargs: Any) -> Any:
        return self._resolve("GET", url)


def _install_async(
    monkeypatch: pytest.MonkeyPatch, routes: dict[str, Any]
) -> _FakeAsyncClient:
    fake = _FakeAsyncClient(routes)
    monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **k: fake)
    return fake


class TestRegistration:
    def test_returns_tokens_for_the_new_user(self, client: TestClient) -> None:
        body = _register(client, "fresh@example.com")

        assert body["access_token"]
        assert body["refresh_token"]
        assert body["user"]["email"] == "fresh@example.com"

    def test_rejects_a_duplicate_email(self, client: TestClient) -> None:
        _register(client, "twice@example.com")

        response = client.post(f"{AUTH}/register", json=_payload("twice@example.com"))

        assert response.status_code == 400
        assert response.json()["detail"] == "Email already registered"

    def test_rejects_a_weak_password(self, client: TestClient) -> None:
        response = client.post(
            f"{AUTH}/register", json=_payload("weak@example.com", password="abc")
        )

        assert response.status_code == 400

    def test_refuses_a_self_assigned_elevated_role(self, client: TestClient) -> None:
        response = client.post(
            f"{AUTH}/register", json=_payload("boss@example.com", role="admin")
        )

        assert response.status_code == 422


class TestSeedAdmin:
    def test_is_disabled_outside_development(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "DEV_ALLOW_SEED", False)

        response = client.post(f"{AUTH}/seed-admin")

        assert response.status_code == 403
        assert response.json()["detail"] == "Seeding disabled"

    def test_requires_seed_credentials(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "DEV_ALLOW_SEED", True)
        monkeypatch.setattr(settings, "DEV_SEED_ADMIN_EMAIL", None)
        monkeypatch.setattr(settings, "DEV_SEED_ADMIN_PASSWORD", None)

        response = client.post(f"{AUTH}/seed-admin")

        assert response.status_code == 400
        assert response.json()["detail"] == "Seed credentials not set"

    def test_creates_the_admin_then_reuses_it(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "DEV_ALLOW_SEED", True)
        monkeypatch.setattr(settings, "DEV_SEED_ADMIN_EMAIL", "seed-admin@example.com")
        monkeypatch.setattr(settings, "DEV_SEED_ADMIN_PASSWORD", PASSWORD)

        first = client.post(f"{AUTH}/seed-admin")
        second = client.post(f"{AUTH}/seed-admin")

        assert first.status_code == 200, first.text
        assert first.json()["user"]["role"] == "admin"
        assert second.status_code == 200, second.text
        assert second.json()["user"]["email"] == "seed-admin@example.com"


class TestLogin:
    def test_rejects_a_bad_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        _make_user(db_session, "login-bad@example.com")

        response = client.post(
            f"{AUTH}/login",
            json={"email": "login-bad@example.com", "password": "WrongPass1!"},
        )

        assert response.status_code == 401
        assert response.json()["detail"] == "Incorrect email or password"

    def test_gates_pending_hosts_with_an_explanation(
        self, client: TestClient, db_session: Session
    ) -> None:
        _make_user(db_session, "pending-host@example.com", role="host", is_active=False)

        response = client.post(
            f"{AUTH}/login",
            json={"email": "pending-host@example.com", "password": PASSWORD},
        )

        assert response.status_code == 403
        assert "regional manager approves" in response.json()["detail"]

    def test_successful_login_syncs_the_supabase_identity(
        self, client: TestClient, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _make_user(db_session, "login-ok@example.com")
        synced: list[tuple[str, str]] = []
        monkeypatch.setattr(
            AuthService,
            "ensure_supabase_user",
            lambda self, email, password: synced.append((email, password)),
        )

        response = client.post(
            f"{AUTH}/login",
            json={"email": "login-ok@example.com", "password": PASSWORD},
        )

        assert response.status_code == 200, response.text
        assert response.json()["user"]["email"] == "login-ok@example.com"
        assert synced == [("login-ok@example.com", PASSWORD)]


class TestLogout:
    def test_ignores_unreadable_tokens(self, client: TestClient) -> None:
        response = client.post(f"{AUTH}/logout", json={"refresh_token": "not-a-jwt"})

        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    def test_ignores_tokens_that_are_not_refresh_tokens(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "logout-access@example.com")
        access = create_access_token(user.id)

        response = client.post(f"{AUTH}/logout", json={"refresh_token": access})

        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    def test_revokes_the_presented_refresh_token(self, client: TestClient) -> None:
        tokens = _register(client, "logout-revoke@example.com")

        client.post(f"{AUTH}/logout", json={"refresh_token": tokens["refresh_token"]})
        retried = client.post(
            f"{AUTH}/refresh", json={"refresh_token": tokens["refresh_token"]}
        )

        assert retried.status_code == 401

    def test_logout_all_ends_every_session(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "logout-all@example.com")
        headers = _bearer(user)
        tokens = client.post(
            f"{AUTH}/login",
            json={"email": "logout-all@example.com", "password": PASSWORD},
        ).json()

        response = client.post(f"{AUTH}/logout-all", headers=headers)

        assert response.status_code == 200, response.text
        assert response.json() == {"status": "ok"}
        # The old access token and refresh token are both dead now.
        assert client.get("/api/v1/profile/me", headers=headers).status_code == 401
        refreshed = client.post(
            f"{AUTH}/refresh", json={"refresh_token": tokens["refresh_token"]}
        )
        assert refreshed.status_code == 401


class TestChangePassword:
    def test_requires_the_current_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "change-wrong@example.com")

        response = client.post(
            f"{AUTH}/change-password",
            json={"current_password": "Nope1234!", "new_password": NEW_PASSWORD},
            headers=_bearer(user),
        )

        assert response.status_code == 400
        assert response.json()["detail"] == "Current password is incorrect"

    def test_rejects_reusing_the_current_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "change-same@example.com")

        response = client.post(
            f"{AUTH}/change-password",
            json={"current_password": PASSWORD, "new_password": PASSWORD},
            headers=_bearer(user),
        )

        assert response.status_code == 400
        assert "must be different" in response.json()["detail"]

    def test_rejects_a_weak_new_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "change-weak@example.com")

        response = client.post(
            f"{AUTH}/change-password",
            json={"current_password": PASSWORD, "new_password": "weak"},
            headers=_bearer(user),
        )

        assert response.status_code == 400

    def test_updates_the_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        user = _make_user(db_session, "change-ok@example.com")

        response = client.post(
            f"{AUTH}/change-password",
            json={"current_password": PASSWORD, "new_password": NEW_PASSWORD},
            headers=_bearer(user),
        )

        assert response.status_code == 200, response.text
        assert response.json()["message"] == "Password updated successfully"
        login = client.post(
            f"{AUTH}/login",
            json={"email": "change-ok@example.com", "password": NEW_PASSWORD},
        )
        assert login.status_code == 200


class TestForgotPassword:
    def test_answers_generically_when_supabase_is_unconfigured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", None)

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "nobody@example.com"}
        )

        assert response.status_code == 200
        assert "If an account exists" in response.json()["message"]

    def test_sends_a_recovery_link_when_configured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        monkeypatch.setattr(
            settings, "RESET_PASSWORD_REDIRECT_URL", "https://app.example.com/reset"
        )
        calls: dict[str, Any] = {}

        monkeypatch.setattr(
            httpx,
            "get",
            lambda *a, **k: _FakeResponse(
                200, {"users": [{"id": "1", "email_confirmed_at": "x"}]}
            ),
        )

        def fake_post(url: str, **kwargs: Any) -> _FakeResponse:
            calls["url"] = url
            calls["json"] = kwargs.get("json")
            return _FakeResponse(200)

        monkeypatch.setattr(httpx, "post", fake_post)

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "member@example.com"}
        )

        assert response.status_code == 200
        assert calls["url"].endswith("/auth/v1/admin/generate_link")
        assert calls["json"]["type"] == "recovery"
        assert calls["json"]["redirect_to"] == "https://app.example.com/reset"

    def test_creates_a_missing_supabase_identity_first(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        monkeypatch.setattr(settings, "RESET_PASSWORD_REDIRECT_URL", None)
        created: dict[str, Any] = {}
        monkeypatch.setattr(
            httpx, "get", lambda *a, **k: _FakeResponse(200, {"users": []})
        )

        def fake_post(url: str, **kwargs: Any) -> _FakeResponse:
            if url.endswith("/auth/v1/admin/users"):
                created["json"] = kwargs.get("json")
            return _FakeResponse(201)

        monkeypatch.setattr(httpx, "post", fake_post)

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "legacy@example.com"}
        )

        assert response.status_code == 200
        assert created["json"]["email"] == "legacy@example.com"
        assert created["json"]["email_confirm"] is True
        assert "redirect_to" not in created["json"]

    def test_tolerates_an_already_existing_supabase_identity(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        monkeypatch.setattr(
            httpx, "get", lambda *a, **k: _FakeResponse(200, {"users": []})
        )
        monkeypatch.setattr(httpx, "post", lambda *a, **k: _FakeResponse(409))

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "dupe@example.com"}
        )

        assert response.status_code == 200

    def test_survives_supabase_server_errors(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        monkeypatch.setattr(httpx, "get", lambda *a, **k: _FakeResponse(500))
        monkeypatch.setattr(
            httpx, "post", lambda *a, **k: _FakeResponse(500, text="boom")
        )

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "broken@example.com"}
        )

        assert response.status_code == 200
        assert "If an account exists" in response.json()["message"]

    def test_survives_supabase_transport_errors(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")

        def exploding_get(*args: Any, **kwargs: Any) -> Any:
            raise httpx.ConnectError("network down")

        monkeypatch.setattr(httpx, "get", exploding_get)
        monkeypatch.setattr(httpx, "post", exploding_get)

        response = client.post(
            f"{AUTH}/forgot-password", json={"email": "offline@example.com"}
        )

        assert response.status_code == 200


class TestSyncPassword:
    def test_skips_when_supabase_is_unconfigured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", None)

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": NEW_PASSWORD},
        )

        assert response.status_code == 200
        assert "skipped" in response.json()["message"]

    def test_rejects_an_invalid_reset_session(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(monkeypatch, {"/auth/v1/user": _FakeResponse(401)})

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "expired", "password": NEW_PASSWORD},
        )

        assert response.status_code == 401
        assert "Invalid or expired reset session" in response.json()["detail"]

    def test_requires_an_email_on_the_reset_session(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(monkeypatch, {"/auth/v1/user": _FakeResponse(200, {})})

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": NEW_PASSWORD},
        )

        assert response.status_code == 400
        assert "Could not determine user" in response.json()["detail"]

    def test_reports_supabase_transport_failures(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(monkeypatch, {"/auth/v1/user": httpx.ConnectError("down")})

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": NEW_PASSWORD},
        )

        assert response.status_code == 502
        assert "Could not verify reset session" in response.json()["detail"]

    def test_updates_the_backend_hash(
        self, client: TestClient, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _make_user(db_session, "sync-ok@example.com")
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(
            monkeypatch,
            {"/auth/v1/user": _FakeResponse(200, {"email": "sync-ok@example.com"})},
        )

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": NEW_PASSWORD},
        )

        assert response.status_code == 200, response.text
        assert response.json()["message"] == "Password updated successfully."
        login = client.post(
            f"{AUTH}/login",
            json={"email": "sync-ok@example.com", "password": NEW_PASSWORD},
        )
        assert login.status_code == 200

    def test_accepts_social_only_accounts(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(
            monkeypatch,
            {"/auth/v1/user": _FakeResponse(200, {"email": "social-only@example.com"})},
        )

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": NEW_PASSWORD},
        )

        assert response.status_code == 200
        assert response.json()["message"] == "Password updated."

    def test_rejects_a_weak_password(
        self, client: TestClient, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _make_user(db_session, "sync-weak@example.com")
        monkeypatch.setattr(settings, "SUPABASE_URL", "https://p.supabase.co")
        monkeypatch.setattr(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key")
        _install_async(
            monkeypatch,
            {"/auth/v1/user": _FakeResponse(200, {"email": "sync-weak@example.com"})},
        )

        response = client.post(
            f"{AUTH}/sync-password",
            json={"supabase_access_token": "token", "password": "weak"},
        )

        assert response.status_code == 400


class TestGoogleOAuth:
    def test_start_is_404_when_unconfigured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", None)

        response = client.get(f"{AUTH}/oauth/google/start")

        assert response.status_code == 404

    def test_start_redirects_to_google(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "client-id")
        monkeypatch.setattr(
            settings, "GOOGLE_REDIRECT_URI", "https://api.example.com/callback"
        )

        response = client.get(f"{AUTH}/oauth/google/start", follow_redirects=False)

        assert response.status_code == 307
        assert response.headers["location"].startswith(
            "https://accounts.google.com/o/oauth2/v2/auth?"
        )
        assert "client-id" in response.headers["location"]

    def test_callback_requires_configuration(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "client-id")
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_SECRET", None)

        response = client.get(f"{AUTH}/oauth/google/callback", params={"code": "abc"})

        assert response.status_code == 500

    def test_callback_issues_tokens(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "client-id")
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_SECRET", "secret")
        monkeypatch.setattr(
            settings, "GOOGLE_REDIRECT_URI", "https://api.example.com/callback"
        )
        monkeypatch.setattr(settings, "FRONTEND_OAUTH_REDIRECT", None)
        _install_async(
            monkeypatch,
            {
                "oauth2.googleapis.com/token": _FakeResponse(
                    200, {"access_token": "google-token"}
                ),
                "openidconnect.googleapis.com": _FakeResponse(
                    200,
                    {
                        "email": "google@example.com",
                        "given_name": "Gita",
                        "family_name": "Sharma",
                    },
                ),
            },
        )

        response = client.get(f"{AUTH}/oauth/google/callback", params={"code": "abc"})

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["access_token"]
        assert body["user"]["email"] == "google@example.com"

    def test_callback_redirects_to_the_frontend_when_configured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "client-id")
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_SECRET", "secret")
        monkeypatch.setattr(
            settings, "GOOGLE_REDIRECT_URI", "https://api.example.com/callback"
        )
        monkeypatch.setattr(
            settings, "FRONTEND_OAUTH_REDIRECT", "https://app.example.com/oauth"
        )
        _install_async(
            monkeypatch,
            {
                "oauth2.googleapis.com/token": _FakeResponse(
                    200, {"access_token": "google-token"}
                ),
                "openidconnect.googleapis.com": _FakeResponse(
                    200, {"email": "google-redirect@example.com"}
                ),
            },
        )

        response = client.get(
            f"{AUTH}/oauth/google/callback",
            params={"code": "abc"},
            follow_redirects=False,
        )

        assert response.status_code == 307
        assert response.headers["location"].startswith("https://app.example.com/oauth?")
        assert "access_token=" in response.headers["location"]

    @pytest.mark.parametrize(
        ("routes", "detail"),
        [
            ({"oauth2.googleapis.com/token": _FakeResponse(400)}, "Failed to exchange"),
            (
                {"oauth2.googleapis.com/token": _FakeResponse(200, {})},
                "Google access token missing",
            ),
            (
                {
                    "oauth2.googleapis.com/token": _FakeResponse(
                        200, {"access_token": "t"}
                    ),
                    "openidconnect.googleapis.com": _FakeResponse(500),
                },
                "Failed to fetch Google userinfo",
            ),
            (
                {
                    "oauth2.googleapis.com/token": _FakeResponse(
                        200, {"access_token": "t"}
                    ),
                    "openidconnect.googleapis.com": _FakeResponse(200, {}),
                },
                "Google user email not available",
            ),
        ],
    )
    def test_callback_reports_upstream_failures(
        self,
        client: TestClient,
        monkeypatch: pytest.MonkeyPatch,
        routes: dict[str, Any],
        detail: str,
    ) -> None:
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "client-id")
        monkeypatch.setattr(settings, "GOOGLE_CLIENT_SECRET", "secret")
        monkeypatch.setattr(
            settings, "GOOGLE_REDIRECT_URI", "https://api.example.com/callback"
        )
        _install_async(monkeypatch, routes)

        response = client.get(f"{AUTH}/oauth/google/callback", params={"code": "abc"})

        assert response.status_code == 400
        assert detail in response.json()["detail"]


class TestFacebookOAuth:
    def test_start_is_404_when_unconfigured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", None)

        response = client.get(f"{AUTH}/oauth/facebook/start")

        assert response.status_code == 404

    def test_start_redirects_to_facebook(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", "fb-id")
        monkeypatch.setattr(
            settings, "FACEBOOK_REDIRECT_URI", "https://api.example.com/callback"
        )

        response = client.get(f"{AUTH}/oauth/facebook/start", follow_redirects=False)

        assert response.status_code == 307
        assert response.headers["location"].startswith(
            "https://www.facebook.com/v17.0/dialog/oauth?"
        )

    def test_callback_requires_configuration(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", "fb-id")
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_SECRET", None)

        response = client.get(f"{AUTH}/oauth/facebook/callback", params={"code": "abc"})

        assert response.status_code == 500

    def test_callback_splits_the_full_name(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", "fb-id")
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_SECRET", "fb-secret")
        monkeypatch.setattr(
            settings, "FACEBOOK_REDIRECT_URI", "https://api.example.com/callback"
        )
        monkeypatch.setattr(settings, "FRONTEND_OAUTH_REDIRECT", None)
        _install_async(
            monkeypatch,
            {
                "oauth/access_token": _FakeResponse(200, {"access_token": "fb-token"}),
                "graph.facebook.com/me": _FakeResponse(
                    200, {"email": "facebook@example.com", "name": "Bikash Thapa Magar"}
                ),
            },
        )

        response = client.get(f"{AUTH}/oauth/facebook/callback", params={"code": "abc"})

        assert response.status_code == 200, response.text
        assert response.json()["user"]["email"] == "facebook@example.com"

    def test_callback_redirects_to_the_frontend_when_configured(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", "fb-id")
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_SECRET", "fb-secret")
        monkeypatch.setattr(
            settings, "FACEBOOK_REDIRECT_URI", "https://api.example.com/callback"
        )
        monkeypatch.setattr(
            settings, "FRONTEND_OAUTH_REDIRECT", "https://app.example.com/oauth"
        )
        _install_async(
            monkeypatch,
            {
                "oauth/access_token": _FakeResponse(200, {"access_token": "fb-token"}),
                "graph.facebook.com/me": _FakeResponse(
                    200, {"email": "fb-redirect@example.com", "name": "Sita"}
                ),
            },
        )

        response = client.get(
            f"{AUTH}/oauth/facebook/callback",
            params={"code": "abc"},
            follow_redirects=False,
        )

        assert response.status_code == 307
        assert response.headers["location"].startswith("https://app.example.com/oauth?")

    @pytest.mark.parametrize(
        ("routes", "detail"),
        [
            ({"oauth/access_token": _FakeResponse(400)}, "Failed to exchange"),
            (
                {"oauth/access_token": _FakeResponse(200, {})},
                "Facebook access token missing",
            ),
            (
                {
                    "oauth/access_token": _FakeResponse(
                        200, {"access_token": "fb-token"}
                    ),
                    "graph.facebook.com/me": _FakeResponse(500),
                },
                "Failed to fetch Facebook userinfo",
            ),
            (
                {
                    "oauth/access_token": _FakeResponse(
                        200, {"access_token": "fb-token"}
                    ),
                    "graph.facebook.com/me": _FakeResponse(200, {"name": "No Email"}),
                },
                "Facebook user email not available",
            ),
        ],
    )
    def test_callback_reports_upstream_failures(
        self,
        client: TestClient,
        monkeypatch: pytest.MonkeyPatch,
        routes: dict[str, Any],
        detail: str,
    ) -> None:
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_ID", "fb-id")
        monkeypatch.setattr(settings, "FACEBOOK_CLIENT_SECRET", "fb-secret")
        monkeypatch.setattr(
            settings, "FACEBOOK_REDIRECT_URI", "https://api.example.com/callback"
        )
        _install_async(monkeypatch, routes)

        response = client.get(f"{AUTH}/oauth/facebook/callback", params={"code": "abc"})

        assert response.status_code == 400
        assert detail in response.json()["detail"]
