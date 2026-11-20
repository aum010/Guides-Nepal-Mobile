from datetime import datetime
import enum

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.core.database import Base


class HostExperience(Base):
    __tablename__ = "host_experiences"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String, nullable=False)
    slug: Mapped[str] = mapped_column(String, nullable=False, index=True)
    city: Mapped[str] = mapped_column(String, nullable=False)
    category: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    duration: Mapped[str] = mapped_column(String, nullable=False)
    hero_image: Mapped[str | None] = mapped_column(String, nullable=True)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, index=True
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )


class HostTour(Base):
    __tablename__ = "host_tours"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String, nullable=False)
    city: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    itinerary: Mapped[str] = mapped_column(Text, nullable=False)
    meeting_point: Mapped[str] = mapped_column(String, nullable=False)
    duration: Mapped[str] = mapped_column(String, nullable=False)
    difficulty: Mapped[str] = mapped_column(String, nullable=False)
    max_guests: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )


class HostBooking(Base):
    __tablename__ = "host_bookings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    host_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    experience_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("host_experiences.id"), nullable=False, index=True
    )
    guest_name: Mapped[str] = mapped_column(String, nullable=False)
    guest_email: Mapped[str] = mapped_column(String, nullable=False)
    guest_phone: Mapped[str | None] = mapped_column(String, nullable=True)
    date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    guests: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    total_price: Mapped[float] = mapped_column(Float, nullable=False, default=0)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String, nullable=False, default="upcoming", index=True
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )


class BookingStatus(str, enum.Enum):
    upcoming = "upcoming"
    accepted = "accepted"
    rejected = "rejected"
    completed = "completed"
    cancelled = "cancelled"
    archived = "archived"


class Booking(Base):
    __tablename__ = "bookings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    guide_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=True, index=True
    )
    # Set when the booking came from a published guide listing, so cancelling
    # can release the seats it took and the guide can see which listing it was.
    # Deliberately a plain integer, like ``experience_id``: the catalogue id
    # space is namespaced and rows outlive their listing.
    guide_listing_id: Mapped[int | None] = mapped_column(
        Integer, nullable=True, index=True
    )
    experience_id: Mapped[int] = mapped_column(Integer, nullable=False)
    experience_title: Mapped[str] = mapped_column(String, nullable=False)
    city: Mapped[str] = mapped_column(String, nullable=False)
    date: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    guests: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    image: Mapped[str | None] = mapped_column(String, nullable=True)
    # native_enum=False keeps the column a plain VARCHAR, which is what the
    # revisions created and what SQLite supports; the Python enum still
    # validates values on the way in and out.
    status: Mapped[BookingStatus] = mapped_column(
        Enum(BookingStatus, native_enum=False),
        default=BookingStatus.upcoming,
        index=True,
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )

    user = relationship("User", foreign_keys=[user_id], backref="bookings")
    guide = relationship(
        "User", foreign_keys=[guide_user_id], backref="assigned_bookings"
    )

    @property
    def guide_name(self) -> str | None:
        """Display name of the assigned guide account, if any — feeds the
        traveler's "Message guide" affordance alongside `guide_user_id`."""
        if self.guide is None:
            return None
        name = f"{self.guide.firstName or ''} {self.guide.lastName or ''}".strip()
        return name or str(self.guide.email or "")
