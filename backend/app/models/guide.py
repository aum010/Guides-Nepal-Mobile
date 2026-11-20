from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, Float, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class Guide(Base):
    __tablename__ = "guides"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    image: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[str] = mapped_column(String, nullable=False)
    rating: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    reviews: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    bio: Mapped[str] = mapped_column(Text, nullable=False)
    languages: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    verified: Mapped[bool | None] = mapped_column(Boolean, default=False)
    lives_in: Mapped[str | None] = mapped_column(String, nullable=True)
    cities: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    gallery: Mapped[Any] = mapped_column(JSON, nullable=False, default=list)
    is_active: Mapped[bool | None] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )
