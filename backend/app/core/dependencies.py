from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from typing import Callable, Optional

from app.core.database import get_db
from app.core.security import decode_access_token
from app.core.roles import has_access
from app.models.user import User


def authenticate_token(db: Session, token: str) -> User:
    """Resolve a bearer token to its user, rejecting revoked tokens.

    The token's `ver` claim must match the user's `token_version`; signing out
    bumps the stored counter, so access tokens issued before that point stop
    working immediately instead of lingering until they expire.
    """
    payload = decode_access_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
        )

    try:
        user_id = int(payload.get("sub", ""))
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
        )

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found"
        )

    if int(payload.get("ver", 0) or 0) != int(user.token_version or 0):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session has ended. Please sign in again.",
        )

    return user


def get_current_user(request: Request, db: Session = Depends(get_db)) -> User:
    auth = request.headers.get("Authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated"
        )
    user = authenticate_token(db, auth.split(" ", 1)[1])
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user"
        )
    return user


def get_optional_user(
    request: Request, db: Session = Depends(get_db)
) -> Optional[User]:
    """Best-effort authentication.

    Returns the authenticated user when a valid bearer token is supplied and
    ``None`` otherwise, so read-only endpoints that feed the public website can
    be served to anonymous visitors while still knowing who is asking.
    """
    try:
        return get_current_user(request=request, db=db)
    except HTTPException:
        return None


def require_role(*allowed_roles: str) -> Callable[..., User]:
    def checker(current_user: User = Depends(get_current_user)) -> User:
        if not has_access(current_user.role, *allowed_roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Role '{current_user.role}' not allowed. Required: {', '.join(allowed_roles)}",
            )
        return current_user

    return checker
