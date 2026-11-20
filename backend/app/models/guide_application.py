from datetime import datetime

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class GuideApplication(Base):
    """Public application from someone signing up as a Guide.

    Kept as a table apart from ``host_applications`` so the two provider
    funnels stay queryable (and reviewable) independently.  Hosts list and
    manage experiences; guides lead tours — they share no columns beyond
    contact info, which is why this is not a single table with a type flag.
    """

    __tablename__ = "guide_applications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    full_name: Mapped[str | None] = mapped_column(String, nullable=True)
    email: Mapped[str | None] = mapped_column(String, index=True, nullable=True)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    city: Mapped[str | None] = mapped_column(String, nullable=True)
    region: Mapped[str | None] = mapped_column(String, nullable=True)
    nin_number: Mapped[str | None] = mapped_column(String, nullable=True)
    documents: Mapped[str | None] = mapped_column(
        String, nullable=True
    )  # file names / summary
    # pending / approved / rejected
    status: Mapped[str | None] = mapped_column(String, default="pending")
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )
