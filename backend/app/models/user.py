from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    firstName = Column(String, nullable=True)
    lastName = Column(String, nullable=True)
    hashed_password = Column(String, nullable=False)
    phone = Column(String, nullable=True)
    role = Column(String, default="traveler")
    region = Column(String, nullable=True)  # for regional heads
    bio = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    # Bumped when a session is ended (sign-out). Access tokens carry the value
    # they were minted with; a mismatch means the token was revoked.
    token_version = Column(Integer, nullable=False, default=0, server_default="0")
    # Same idea for refresh tokens. Only a "sign out everywhere" bumps it, so
    # an ordinary sign-out leaves other devices able to renew.
    session_version = Column(Integer, nullable=False, default=0, server_default="0")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
