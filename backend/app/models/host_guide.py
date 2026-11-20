"""Host-managed guides and experience assignments.

A Host can create a full guide account (login-capable ``users`` row with
``role='guide'``) together with its public ``guides`` catalog profile and a
``guide_applications`` verification record — mirroring the exact data the
frontend ``BecomeGuidePage`` collects.  Ownership is tracked in
``host_guides`` so each Host only sees and manage their own guides, and
``host_experience_guides`` links one guide profile to one host experience
so travelers see the assigned guide on the frontend.
"""

from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class HostGuide(Base):
    """Ownership link between a Host, the guide login account, and catalog profile."""

    __tablename__ = "host_guides"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    guide_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=True, index=True
    )
    guide_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("guides.id"), nullable=True, index=True
    )
    # Snapshot of the registration fields (mirrors BecomeGuidePage + GuideApplication)
    full_name: Mapped[str] = mapped_column(String, nullable=False)
    email: Mapped[str] = mapped_column(String, nullable=False, index=True)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    nin_number: Mapped[str | None] = mapped_column(String, nullable=True)
    city: Mapped[str | None] = mapped_column(String, nullable=True)
    region: Mapped[str | None] = mapped_column(String, nullable=True)
    documents: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    status: Mapped[str] = mapped_column(
        String, nullable=False, default="active"
    )  # active | suspended
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )


class HostExperienceGuide(Base):
    """Assigns one guide catalog profile to one host experience."""

    __tablename__ = "host_experience_guides"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    experience_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("host_experiences.id"), nullable=False, index=True
    )
    guide_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("guides.id"), nullable=False, index=True
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
