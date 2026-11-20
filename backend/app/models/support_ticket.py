from datetime import datetime

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class SupportTicket(Base):
    __tablename__ = "support_tickets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    subject: Mapped[str | None] = mapped_column(String, nullable=True)
    description: Mapped[str | None] = mapped_column(String, nullable=True)
    customer_name: Mapped[str | None] = mapped_column(String, nullable=True)
    customer_email: Mapped[str | None] = mapped_column(
        String, index=True, nullable=True
    )
    # open / in_progress / resolved / closed
    status: Mapped[str | None] = mapped_column(String, default="open")
    # low / medium / high / urgent
    priority: Mapped[str | None] = mapped_column(String, default="medium")
    assigned_to: Mapped[str | None] = mapped_column(String, nullable=True)
    # free-text resolution note entered by support staff
    resolution: Mapped[str | None] = mapped_column(String, nullable=True)
    # timestamp set when a resolution note is provided
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), onupdate=func.now()
    )
