"""Cross-cutting middleware: security headers, the production-only HSTS and
HTTPS gate, suspicious-input blocking, request logging, and error
passthrough."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings

HEALTH = "/health"


class TestSecurityHeaders:
    def test_every_response_carries_the_security_headers(
        self, client: TestClient
    ) -> None:
        response = client.get(HEALTH)
        assert response.status_code == 200
        assert response.headers["X-Content-Type-Options"] == "nosniff"
        assert response.headers["X-Frame-Options"] == "DENY"
        assert response.headers["X-XSS-Protection"] == "1; mode=block"
        assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
        assert "camera=()" in response.headers["Permissions-Policy"]
        assert "default-src 'self'" in response.headers["Content-Security-Policy"]

    def test_hsts_applies_and_http_is_refused_in_production_mode(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # DEBUG gates both HSTS and HTTPS enforcement; flip it for the request
        # only, then let monkeypatch restore the property.
        monkeypatch.setattr(type(settings), "DEBUG", False, raising=False)

        allowed = client.get(HEALTH, headers={"x-forwarded-proto": "https"})
        assert allowed.status_code == 200
        assert allowed.headers["Strict-Transport-Security"] == (
            "max-age=31536000; includeSubDomains; preload"
        )

        refused = client.get(HEALTH)
        assert refused.status_code == 403
        assert refused.json()["detail"] == "HTTPS required"

    def test_debug_mode_sends_no_hsts_header(self, client: TestClient) -> None:
        assert settings.DEBUG is True
        assert "Strict-Transport-Security" not in client.get(HEALTH).headers


class TestInputValidation:
    def test_sql_like_probe_in_the_path_is_blocked(self, client: TestClient) -> None:
        # Query strings are re-encoded before they reach the check, so the
        # probe has to travel in the (decoded) path.
        response = client.get("/health/exec(1)")
        assert response.status_code == 400
        assert response.json() == {"detail": "Invalid request"}

    def test_double_encoded_path_traversal_is_blocked(self, client: TestClient) -> None:
        # Single-encoded dots are normalized by the client; double-encoding
        # survives to the server, where the middleware sees "%2e%2e".
        response = client.get("/health/x%252e%252e%252fadmin")
        assert response.status_code == 400

    def test_command_injection_chars_in_the_path_are_blocked(
        self, client: TestClient
    ) -> None:
        response = client.get("/health/$(id)")
        assert response.status_code == 400

    def test_null_byte_in_the_query_is_blocked(self, client: TestClient) -> None:
        response = client.get(HEALTH, params={"q": "\x00"})
        assert response.status_code == 400

    def test_benign_requests_pass_through(self, client: TestClient) -> None:
        response = client.get(HEALTH, params={"q": "ordinary search"})
        assert response.status_code == 200


class TestRequestLogging:
    def test_logging_can_be_switched_off(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "ENABLE_REQUEST_LOGGING", False)
        assert client.get(HEALTH).status_code == 200

    def test_handler_exceptions_pass_through_the_middleware(self) -> None:
        from app.main import app as main_app

        def _boom() -> dict:
            raise RuntimeError("middleware probe")

        probe = "/__middleware_boom__"
        main_app.add_api_route(probe, _boom, methods=["GET"])
        try:
            with TestClient(main_app, raise_server_exceptions=False) as probe_client:
                assert probe_client.get(probe).status_code == 500
        finally:
            main_app.router.routes = [
                route
                for route in main_app.router.routes
                if getattr(route, "path", None) != probe
            ]
