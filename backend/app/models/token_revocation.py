from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.core.database import Base


class RevokedToken(Base):
    """A refresh token that was explicitly revoked by signing out.

    Refresh tokens are self-contained JWTs, so there is no server-side session
    row to delete. Each token carries a `jti`; `/auth/logout` records it here
    and `/auth/refresh` refuses to mint new sessions from it. Rows are pruned
    once the token would have expired on its own.
    """

    __tablename__ = "revoked_tokens"

    id = Column(Integer, primary_key=True, index=True)
    jti = Column(String, unique=True, index=True, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, server_default=func.now())
