from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.core.database import Base


class Conversation(Base):
    """A direct message thread between exactly two user accounts.

    The pair is stored in canonical order (``user_a_id`` < ``user_b_id``)
    with a unique constraint, so opening a conversation twice — from a
    trip on one side and from the guide's requests on the other — reuses
    one thread instead of forking two.
    """

    __tablename__ = "conversations"
    __table_args__ = (
        UniqueConstraint("user_a_id", "user_b_id", name="uq_conversations_pair"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_a_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    user_b_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime, server_default=func.now()
    )

    messages = relationship(
        "Message",
        backref="conversation",
        order_by="Message.id",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    def other_user_id(self, viewer_id: int) -> int:
        """The counterpart for [viewer_id], who must be a participant."""
        if viewer_id == self.user_a_id:
            return self.user_b_id
        if viewer_id == self.user_b_id:
            return self.user_a_id
        raise ValueError(f"user {viewer_id} is not part of conversation {self.id}")


class Message(Base):
    """One chat message. ``read_at`` is set when the *recipient* fetches
    the thread, which is what drives unread counts on the inbox list."""

    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    conversation_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("conversations.id"), nullable=False, index=True
    )
    sender_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False, index=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime | None] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
