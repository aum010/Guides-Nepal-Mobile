"""
Security utilities for authentication, password hashing, and token management
"""

from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Union, cast
import re
import logging
from uuid import uuid4

import bcrypt
from jose import jwt
from jose.exceptions import JWTError

from app.core.config import settings

logger = logging.getLogger(__name__)

# bcrypt only uses the first 72 bytes of a password. bcrypt >= 4.1 raises instead
# of silently truncating, so we truncate explicitly and consistently for both
# hashing and verification.
_BCRYPT_MAX_BYTES = 72


def _to_bcrypt_bytes(password: str) -> bytes:
    return password.encode("utf-8")[:_BCRYPT_MAX_BYTES]


def validate_password_strength(password: str) -> tuple[bool, str]:
    """
    Validate password meets security requirements
    Returns: (is_valid, error_message)
    """
    if len(password) < settings.MIN_PASSWORD_LENGTH:
        return (
            False,
            f"Password must be at least {settings.MIN_PASSWORD_LENGTH} characters",
        )

    if settings.REQUIRE_PASSWORD_UPPERCASE and not re.search(r"[A-Z]", password):
        return False, "Password must contain at least one uppercase letter"

    if settings.REQUIRE_PASSWORD_NUMBERS and not re.search(r"[0-9]", password):
        return False, "Password must contain at least one number"

    if settings.REQUIRE_PASSWORD_SPECIAL and not re.search(
        r"[!@#$%^&*()_+\-=\[\]{};:,.<>?]", password
    ):
        return False, "Password must contain at least one special character (!@#$%^&*)"

    return True, ""


def create_access_token(
    subject: Union[str, Any],
    expires_delta: Optional[timedelta] = None,
    token_version: int = 0,
) -> str:
    """Create JWT access token with expiration.

    `token_version` is compared against the user's stored counter on every
    authenticated request, so ending a session can invalidate access tokens
    that were already handed out (see `POST /auth/logout`).
    """
    if expires_delta:
        expire = datetime.now(timezone.utc).replace(tzinfo=None) + expires_delta
    else:
        expire = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(
            minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
        )

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "access",
        "ver": int(token_version or 0),
    }
    encoded_jwt = jwt.encode(
        to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM
    )
    return cast(str, encoded_jwt)


def create_refresh_token(
    subject: Union[str, Any],
    expires_delta: Optional[timedelta] = None,
    session_version: int = 0,
) -> str:
    """Create JWT refresh token with longer expiration.

    A unique `jti` identifies the token so it can be revoked individually at
    sign-out (see `app/models/token_revocation.py`). `session_version` is
    compared against the user's stored counter on every exchange, so a
    "sign out everywhere" invalidates all refresh tokens already issued.
    """
    if expires_delta:
        expire = datetime.now(timezone.utc).replace(tzinfo=None) + expires_delta
    else:
        expire = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(
            days=settings.REFRESH_TOKEN_EXPIRE_DAYS
        )

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "refresh",
        "jti": uuid4().hex,
        "sver": int(session_version or 0),
    }
    encoded_jwt = jwt.encode(
        to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM
    )
    return cast(str, encoded_jwt)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify plain password against hashed password using bcrypt"""
    try:
        return bcrypt.checkpw(
            _to_bcrypt_bytes(plain_password),
            hashed_password.encode("utf-8"),
        )
    except Exception as e:
        logger.error(f"Password verification error: {e}")
        return False


def get_password_hash(password: str) -> str:
    """Hash password using bcrypt with cost factor 12 (secure)"""
    hashed = bcrypt.hashpw(_to_bcrypt_bytes(password), bcrypt.gensalt(rounds=12))
    return hashed.decode("utf-8")


def decode_access_token(token: str) -> Optional[dict]:
    """Return the claims of a valid access token, else `None`.

    Rejects expired tokens, tampered tokens and tokens of another type. The
    caller is responsible for checking the claims against stored state (e.g.
    `ver` against `User.token_version`).
    """
    try:
        payload: dict[str, Any] = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
    except JWTError as e:
        logger.debug(f"JWT error: {e}")
        return None

    expected_type = "access"  # nosec B105 - token-type literal, not a password
    if payload.get("type") != expected_type:
        logger.warning(f"Invalid token type: {payload.get('type')}")
        return None
    return payload


def get_user_id_from_token(token: str) -> Optional[int]:
    """Extract and verify user ID from JWT token"""
    payload = decode_access_token(token)
    if payload is None:
        return None

    sub = payload.get("sub")
    if sub is None:
        return None

    try:
        return int(sub)
    except (TypeError, ValueError):
        logger.warning(f"Invalid user ID in token: {sub}")
        return None


def verify_token_and_get_user_id(token: str) -> Optional[int]:
    """Alias for get_user_id_from_token for backwards compatibility"""
    return get_user_id_from_token(token)


def is_token_expired(token: str) -> bool:
    """Check if token is expired"""
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        exp = payload.get("exp")
        if exp is None:
            return True
        # Pure instant comparison — both sides aware, same truth value as
        # the old naive-UTC pair, without the deprecated constructors.
        return datetime.fromtimestamp(exp, timezone.utc) < datetime.now(timezone.utc)
    except JWTError:
        return True


def sanitize_input(input_string: str, max_length: int = 1000) -> str:
    """
    Sanitize user input to prevent XSS and injection attacks
    """
    if not isinstance(input_string, str):
        return ""

    # Limit length
    input_string = input_string[:max_length]

    # Remove null bytes
    input_string = input_string.replace("\x00", "")

    # Remove script tags (basic XSS protection)
    dangerous_patterns = ["<script", "</script>", "javascript:", "onerror=", "onload="]
    for pattern in dangerous_patterns:
        if pattern.lower() in input_string.lower():
            logger.warning(f"Dangerous pattern detected in input: {pattern}")
            input_string = input_string.replace(pattern, "")

    return input_string
