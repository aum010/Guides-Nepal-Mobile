from datetime import datetime
from typing import Any

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class GuideListing(Base):
    """Experience listing owned by a guide user account.

    Unlike the public ``guides`` catalog table (display-only profiles), this
    table is keyed by ``guide_user_id`` so each signed-in guide can list and
    manage their own trekking routes, travel tours, or specialized activities
    — including the per-listing ``max_guests`` capacity.
    """

    __tablename__ = "guide_listings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    guide_user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    # URL segment for the public catalogue (``/experiences/listing-<slug>``).
    # Generated on create and kept stable afterwards, so a title edit never
    # breaks a link a traveller has already shared.
    slug: Mapped[str] = mapped_column(
        String,
        nullable=False,
        index=True,
        unique=True,
        default="",
        # Mirrors the column the revision created; a row inserted without a
        # slug must collide on the unique index rather than get NULL.
        server_default="",
    )
    title: Mapped[str] = mapped_column(String, nullable=False)
    category: Mapped[str] = mapped_column(
        String, nullable=False, default="tour"
    )  # trekking | tour | specialized
    city: Mapped[str] = mapped_column(
        String, nullable=False, default="Kathmandu"
    )  # area of expertise / event location
    area: Mapped[str | None] = mapped_column(
        String, nullable=True
    )  # e.g. "Annapurna Circuit"
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    itinerary: Mapped[str | None] = mapped_column(Text, nullable=True)
    meeting_point: Mapped[str | None] = mapped_column(String, nullable=True)
    duration: Mapped[str] = mapped_column(String, nullable=False, default="1 day")
    difficulty: Mapped[str] = mapped_column(String, nullable=False, default="Easy")
    price: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    max_guests: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    booked_guests: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Public photo for the catalogue card and detail page, stored as a path
    # under ``/uploads`` (see ``app.core.storage``). Null falls back to a
    # category photo rather than an empty card.
    hero_image: Mapped[str | None] = mapped_column(String, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )

    # The capacity guard and the console's active-listing lookup are indexed by
    # the revisions; declaring them here keeps the models and migrations equal.
    __table_args__ = (
        Index("ix_guide_listings_capacity", "max_guests", "booked_guests"),
        Index("ix_guide_listings_guide_active", "guide_user_id", "is_active"),
    )


class GuideStatusUpdate(Base):
    """Real-time post from a guide about bookings / capacity / schedule.

    ``update_type`` is one of: availability | capacity | booking | schedule | announcement.
    """

    __tablename__ = "guide_status_updates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    guide_user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    listing_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("guide_listings.id"), nullable=True, index=True
    )
    update_type: Mapped[str] = mapped_column(
        String, nullable=False, default="announcement"
    )
    message: Mapped[str] = mapped_column(Text, nullable=False)
    area: Mapped[str | None] = mapped_column(String, nullable=True)
    event_date: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    current_capacity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    max_capacity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        Index("ix_guide_status_updates_type_date", "guide_user_id", "created_at"),
    )


class GuideProfile(Base):
    """Onboarding profile for a guide user account (one row per user)."""

    __tablename__ = "guide_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    guide_user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, unique=True, index=True
    )
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    expertise_areas: Mapped[Any] = mapped_column(
        JSON, nullable=False, default=list
    )  # e.g. ["trekking", "tour", "specialized"]
    cities: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    languages: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    years_experience: Mapped[str | None] = mapped_column(String, nullable=True)
    default_max_guests: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    onboarding_completed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )
