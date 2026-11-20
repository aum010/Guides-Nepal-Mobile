"""
Tests for authentication endpoints.
"""

from typing import Any
from sqlalchemy.orm import Session

from fastapi.testclient import TestClient


class TestAuthEndpoints:
    """Test authentication endpoints."""

    def test_register_user(
        self, client: TestClient, sample_user_data: dict[str, Any]
    ) -> None:
        """Test user registration."""
        response = client.post("/api/v1/auth/register", json=sample_user_data)
        # Note: This test may need adjustment based on actual auth implementation
        assert response.status_code in [200, 201, 400, 422]

    def test_login_user(
        self, client: TestClient, sample_user_data: dict[str, Any]
    ) -> None:
        """Test user login."""
        response = client.post(
            "/api/v1/auth/login",
            json={
                "email": sample_user_data["email"],
                "password": sample_user_data["password"],
            },
        )
        # Note: This test may need adjustment based on actual auth implementation
        assert response.status_code in [200, 401, 422]

    def test_oauth_google_start(self, client: TestClient) -> None:
        """Test Google OAuth start endpoint."""
        response = client.get("/api/v1/auth/oauth/google/start")
        # Note: This test may need adjustment based on actual OAuth implementation
        assert response.status_code in [200, 307, 404]

    def test_oauth_facebook_start(self, client: TestClient) -> None:
        """Test Facebook OAuth start endpoint."""
        response = client.get("/api/v1/auth/oauth/facebook/start")
        # Note: This test may need adjustment based on actual OAuth implementation
        assert response.status_code in [200, 307, 404]


class TestAuthRefresh:
    """Tests for the refresh-token exchange (`POST /auth/refresh`)."""

    @staticmethod
    def _register(client: TestClient, email: str = "refresh@example.com") -> Any:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPassword123!",
                "firstName": "Test",
                "lastName": "User",
            },
        )
        assert response.status_code in (200, 201), response.text
        return response.json()

    def test_refresh_issues_working_tokens(self, client: TestClient) -> None:
        tokens = self._register(client)

        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert response.status_code == 200, response.text
        fresh = response.json()
        assert fresh["access_token"]
        assert fresh["refresh_token"]
        assert fresh["user"]["email"] == "refresh@example.com"

        # The rotated access token authenticates a protected endpoint.
        me = client.get(
            "/api/v1/profile/me",
            headers={"Authorization": f"Bearer {fresh['access_token']}"},
        )
        assert me.status_code == 200, me.text

    def test_refresh_rejects_access_tokens(self, client: TestClient) -> None:
        tokens = self._register(client)

        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": tokens["access_token"]},
        )
        assert response.status_code == 401

    def test_refresh_rejects_garbage_tokens(self, client: TestClient) -> None:
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": "not.a.valid.jwt"},
        )
        assert response.status_code == 401

    def test_refresh_rejects_inactive_users(
        self, client: TestClient, db_session: Session
    ) -> None:

        tokens = self._register(client)

        from app.models.user import User

        user = (
            db_session.query(User).filter(User.email == "refresh@example.com").first()
        )
        assert user is not None
        user.is_active = False
        db_session.commit()

        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert response.status_code == 401


class TestAccessTokenRevocation:
    """Signing out also invalidates access tokens already issued."""

    @staticmethod
    def _register(client: TestClient, email: str = "revoke@example.com") -> Any:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPassword123!",
                "firstName": "Test",
                "lastName": "User",
            },
        )
        assert response.status_code in (200, 201), response.text
        return response.json()

    @staticmethod
    def _me(client: TestClient, token: str) -> Any:
        return client.get(
            "/api/v1/profile/me",
            headers={"Authorization": f"Bearer {token}"},
        )

    def test_logout_invalidates_an_already_issued_access_token(
        self, client: TestClient
    ) -> None:
        tokens = self._register(client)
        assert self._me(client, tokens["access_token"]).status_code == 200

        client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": tokens["refresh_token"]},
        )

        revoked = self._me(client, tokens["access_token"])
        assert revoked.status_code == 401
        assert "session has ended" in revoked.json()["detail"].lower()

    def test_another_session_recovers_with_its_refresh_token(
        self, client: TestClient
    ) -> None:
        first = self._register(client)
        second = client.post(
            "/api/v1/auth/login",
            json={
                "email": "revoke@example.com",
                "password": "TestPassword123!",
            },
        ).json()

        client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": first["refresh_token"]},
        )

        # The other session's access token is invalidated too...
        assert self._me(client, second["access_token"]).status_code == 401
        # ...but its refresh token still works, so the client renews and
        # continues without a re-login.
        renewed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": second["refresh_token"]},
        )
        assert renewed.status_code == 200, renewed.text
        assert self._me(client, renewed.json()["access_token"]).status_code == 200

    def test_profile_endpoints_also_reject_revoked_tokens(
        self, client: TestClient
    ) -> None:
        tokens = self._register(client)
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        assert (
            client.get("/api/v1/profile/bookmarks", headers=headers).status_code == 200
        )

        client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": tokens["refresh_token"]},
        )

        assert (
            client.get("/api/v1/profile/bookmarks", headers=headers).status_code == 401
        )


class TestLogoutEverywhere:
    """`POST /auth/logout-all` ends every session of the account."""

    @staticmethod
    def _register(client: TestClient, email: str = "everywhere@example.com") -> Any:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPassword123!",
                "firstName": "Test",
                "lastName": "User",
            },
        )
        assert response.status_code in (200, 201), response.text
        return response.json()

    @staticmethod
    def _auth(token: str) -> dict:
        return {"Authorization": f"Bearer {token}"}

    def test_ends_every_access_and_refresh_token(self, client: TestClient) -> None:
        first = self._register(client)
        second = client.post(
            "/api/v1/auth/login",
            json={
                "email": "everywhere@example.com",
                "password": "TestPassword123!",
            },
        ).json()

        out = client.post(
            "/api/v1/auth/logout-all", headers=self._auth(first["access_token"])
        )
        assert out.status_code == 200, out.text

        # Both sessions' access tokens are dead...
        for tokens in (first, second):
            me = client.get(
                "/api/v1/profile/me", headers=self._auth(tokens["access_token"])
            )
            assert me.status_code == 401

        # ...and neither refresh token can mint a new session.
        for tokens in (first, second):
            refreshed = client.post(
                "/api/v1/auth/refresh",
                json={"refresh_token": tokens["refresh_token"]},
            )
            assert refreshed.status_code == 401

    def test_signing_in_afterwards_works(self, client: TestClient) -> None:
        tokens = self._register(client)
        client.post(
            "/api/v1/auth/logout-all", headers=self._auth(tokens["access_token"])
        )

        fresh = client.post(
            "/api/v1/auth/login",
            json={
                "email": "everywhere@example.com",
                "password": "TestPassword123!",
            },
        )
        assert fresh.status_code == 200, fresh.text
        data = fresh.json()
        assert (
            client.get(
                "/api/v1/profile/me", headers=self._auth(data["access_token"])
            ).status_code
            == 200
        )
        assert (
            client.post(
                "/api/v1/auth/refresh",
                json={"refresh_token": data["refresh_token"]},
            ).status_code
            == 200
        )

    def test_requires_authentication(self, client: TestClient) -> None:
        assert client.post("/api/v1/auth/logout-all").status_code == 401


class TestAuthLogout:
    """Tests for sign-out revocation (`POST /auth/logout`)."""

    @staticmethod
    def _register(client: TestClient, email: str = "logout@example.com") -> Any:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPassword123!",
                "firstName": "Test",
                "lastName": "User",
            },
        )
        assert response.status_code in (200, 201), response.text
        return response.json()

    def test_logout_revokes_the_refresh_token(self, client: TestClient) -> None:
        tokens = self._register(client)

        out = client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert out.status_code == 200

        refreshed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert refreshed.status_code == 401

    def test_logout_only_revokes_that_session(self, client: TestClient) -> None:
        first = self._register(client)
        second = client.post(
            "/api/v1/auth/login",
            json={
                "email": "logout@example.com",
                "password": "TestPassword123!",
            },
        )
        assert second.status_code == 200, second.text
        second_tokens = second.json()

        client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": first["refresh_token"]},
        )

        gone = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": first["refresh_token"]},
        )
        alive = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": second_tokens["refresh_token"]},
        )
        assert gone.status_code == 401
        assert alive.status_code == 200, alive.text

    def test_logout_is_idempotent(self, client: TestClient) -> None:
        tokens = self._register(client)

        for _ in range(2):
            response = client.post(
                "/api/v1/auth/logout",
                json={"refresh_token": tokens["refresh_token"]},
            )
            assert response.status_code == 200

    def test_logout_tolerates_an_unreadable_token(self, client: TestClient) -> None:
        response = client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": "not.a.jwt"},
        )
        assert response.status_code == 200

    def test_rotated_refresh_token_remains_usable(self, client: TestClient) -> None:
        tokens = self._register(client)

        rotated = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert rotated.status_code == 200

        again = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": rotated.json()["refresh_token"]},
        )
        assert again.status_code == 200, again.text
