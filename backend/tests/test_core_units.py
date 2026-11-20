"""Unit tests for the pure logic in `app.core`.

The endpoint tests exercise these helpers only incidentally; these cases pin
down the branches they never reach: password policy failures, token
edge cases, input sanitizing, the Postgres URL normalizer, the model
registry, and the global exception handler.
"""

from datetime import timedelta
from sqlalchemy.orm import Session

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt

from app.core.config import settings
from app.core.database import _normalize_db_url, get_db
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    get_password_hash,
    get_user_id_from_token,
    is_token_expired,
    sanitize_input,
    validate_password_strength,
    verify_password,
    verify_token_and_get_user_id,
)


class TestPasswordStrength:
    def test_too_short_is_rejected(self) -> None:
        ok, msg = validate_password_strength("Sh1!")
        assert not ok
        assert str(settings.MIN_PASSWORD_LENGTH) in msg

    def test_missing_uppercase_is_rejected(self) -> None:
        ok, msg = validate_password_strength("alllower1!")
        assert not ok
        assert "uppercase" in msg

    def test_missing_number_is_rejected(self) -> None:
        ok, msg = validate_password_strength("NoDigitsHere!")
        assert not ok
        assert "number" in msg

    def test_missing_special_character_is_rejected(self) -> None:
        ok, msg = validate_password_strength("NoSpecial123")
        assert not ok
        assert "special character" in msg

    def test_strong_password_is_accepted(self) -> None:
        ok, msg = validate_password_strength("StrongPass1!")
        assert ok, msg
        assert msg == ""


class TestTokenHelpers:
    def test_access_token_with_explicit_expiry_round_trips(self) -> None:
        token = create_access_token(
            42, expires_delta=timedelta(minutes=5), token_version=3
        )
        payload = decode_access_token(token)
        assert payload is not None
        assert payload["sub"] == "42"
        assert payload["ver"] == 3

    def test_refresh_token_with_explicit_expiry_round_trips(self) -> None:
        token = create_refresh_token(
            7, expires_delta=timedelta(days=2), session_version=1
        )
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        assert payload["type"] == "refresh"
        assert payload["sver"] == 1
        assert payload["jti"]

    def test_verify_password_rejects_wrong_password(self) -> None:
        hashed = get_password_hash("RightPass1!")
        assert not verify_password("WrongPass1!", hashed)

    def test_verify_password_survives_a_malformed_hash(self) -> None:
        assert not verify_password("Whatever1!", "not-a-bcrypt-hash")

    def test_decode_rejects_a_refresh_token(self) -> None:
        refresh = create_refresh_token(9)
        assert decode_access_token(refresh) is None

    def test_decode_rejects_garbage(self) -> None:
        assert decode_access_token("not.a.jwt") is None

    def test_user_id_is_extracted_from_a_valid_token(self) -> None:
        token = create_access_token(5)
        assert get_user_id_from_token(token) == 5
        assert verify_token_and_get_user_id(token) == 5

    def test_user_id_extraction_rejects_a_non_integer_subject(self) -> None:
        token = jwt.encode(
            {
                "sub": "not-a-number",
                "type": "access",
                "exp": 4102444800,
            },
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        assert get_user_id_from_token(token) is None

    def test_user_id_extraction_requires_a_subject(self) -> None:
        token = jwt.encode(
            {"type": "access", "exp": 4102444800},
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        assert get_user_id_from_token(token) is None

    def test_is_token_expired_handles_expired_tokens(self) -> None:
        expired = create_access_token(1, expires_delta=timedelta(minutes=-5))
        assert is_token_expired(expired) is True

    def test_is_token_expired_accepts_fresh_tokens(self) -> None:
        fresh = create_access_token(1)
        assert is_token_expired(fresh) is False

    def test_is_token_expired_treats_a_missing_exp_as_expired(self) -> None:
        no_exp = jwt.encode(
            {"sub": "1", "type": "access"},
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        assert is_token_expired(no_exp) is True

    def test_is_token_expired_rejects_garbage(self) -> None:
        assert is_token_expired("nonsense") is True


class TestSanitizeInput:
    def test_non_strings_become_empty(self) -> None:
        assert sanitize_input(123) == ""  # type: ignore[arg-type]

    def test_length_is_bounded(self) -> None:
        assert sanitize_input("a" * 50, max_length=10) == "a" * 10

    def test_null_bytes_are_removed(self) -> None:
        assert sanitize_input("ok\x00value") == "okvalue"

    def test_script_and_javascript_vectors_are_stripped(self) -> None:
        dirty = "<script>alert(1)</script> javascript:evil onerror=x onload=y"
        clean = sanitize_input(dirty)
        for needle in ("<script", "</script>", "javascript:", "onerror=", "onload="):
            assert needle not in clean.lower()

    def test_clean_text_passes_through(self) -> None:
        assert sanitize_input("Namaste! 100%") == "Namaste! 100%"


class TestNormalizeDbUrl:
    def test_remote_postgres_forces_ssl_and_a_timeout(self) -> None:
        url = _normalize_db_url("postgresql://user:pass@db.example.com:5432/guides")
        assert url.startswith("postgresql+psycopg2://")
        assert "sslmode=require" in url
        assert "connect_timeout=10" in url

    def test_localhost_postgres_does_not_force_ssl(self) -> None:
        url = _normalize_db_url("postgresql://postgres:postgres@localhost:5432/g")
        assert "sslmode=disable" in url

    def test_docker_service_names_are_treated_as_local(self) -> None:
        assert "sslmode=disable" in _normalize_db_url("postgres://u:p@db:5432/g")
        assert "sslmode=disable" in _normalize_db_url(
            "postgres://u:p@host.docker.internal:5432/g"
        )

    def test_an_explicit_sslmode_is_preserved(self) -> None:
        url = _normalize_db_url("postgresql://user@server.example.com/db?sslmode=allow")
        assert "sslmode=allow" in url
        assert "sslmode=require" not in url

    def test_non_postgres_urls_pass_through_unchanged(self) -> None:
        assert _normalize_db_url("sqlite:///./local.db") == "sqlite:///./local.db"


class TestSessionFactory:
    def test_get_db_yields_a_session_and_closes_it(self) -> None:
        gen = get_db()
        session = next(gen)
        try:
            assert session is not None
        finally:
            gen.close()  # drives the generator's finally: db.close()


def test_model_registry_imports_every_model() -> None:
    from app.core.database import Base
    from app.models import DB as registry

    assert "User" in registry.__all__
    assert "ExperienceChangeRequest" in registry.__all__
    # Importing the registry must populate the full table catalog.
    assert "users" in Base.metadata.tables
    assert "bookings" in Base.metadata.tables


class TestAuthenticateToken:
    """The shared bearer-token resolver behind every protected route."""

    def test_garbage_token_is_rejected(self, db_session: Session) -> None:
        from app.core.dependencies import authenticate_token

        with pytest.raises(HTTPException) as excinfo:
            authenticate_token(db_session, "not.a.jwt")
        assert excinfo.value.status_code == 401

    def test_non_integer_subject_is_rejected(self, db_session: Session) -> None:
        from app.core.dependencies import authenticate_token

        token = jwt.encode(
            {"sub": "abc", "type": "access", "exp": 4102444800},
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        with pytest.raises(HTTPException) as excinfo:
            authenticate_token(db_session, token)
        assert excinfo.value.status_code == 401

    def test_token_for_a_deleted_user_is_rejected(self, db_session: Session) -> None:
        from app.core.dependencies import authenticate_token

        token = create_access_token(999999)
        with pytest.raises(HTTPException) as excinfo:
            authenticate_token(db_session, token)
        assert excinfo.value.status_code == 401
        assert "not found" in excinfo.value.detail.lower()


def test_global_exception_handler_returns_500_for_unhandled_errors() -> None:
    """The handler masks internals; with DEBUG on it re-raises so the
    server-error path still surfaces — either way the probe must not 200."""
    from app.main import app as main_app

    def _boom() -> dict:
        raise RuntimeError("probe failure")

    probe = "/__test_boom__"
    main_app.add_api_route(probe, _boom, methods=["GET"])
    try:
        with TestClient(main_app, raise_server_exceptions=False) as probe_client:
            response = probe_client.get(probe)
            assert response.status_code == 500
    finally:
        main_app.router.routes = [
            route
            for route in main_app.router.routes
            if getattr(route, "path", None) != probe
        ]
