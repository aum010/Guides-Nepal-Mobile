from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class HostApplication(Base):
    __tablename__ = "host_applications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_name: Mapped[str | None] = mapped_column(String, nullable=True)
    email: Mapped[str | None] = mapped_column(String, index=True, nullable=True)
    city: Mapped[str | None] = mapped_column(String, nullable=True)
    region: Mapped[str | None] = mapped_column(String, nullable=True)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    experience: Mapped[str | None] = mapped_column(String, nullable=True)
    # pending / approved / rejected
    status: Mapped[str | None] = mapped_column(String, default="pending")
    # SHA-256 hex of a server-issued setup token. Set when a credential invite
    # is issued for a pending application, cleared once the password is set,
    # so the invite link is single-use.
    credential_token_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    # bcrypt hash of the host's chosen password, captured at application time.
    # The login account is only *created* (role=host, is_active=True) when a
    # regional-head/admin approves — never before.
    credential_password_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    # Extra application detail captured by the multi-step wizard (JSON string).
    details_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    # id of the users row minted on approval (None until approved).
    user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # who approved + optional note, for the audit trail.
    reviewed_by: Mapped[str | None] = mapped_column(String, nullable=True)
    review_note: Mapped[str | None] = mapped_column(String, nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )
