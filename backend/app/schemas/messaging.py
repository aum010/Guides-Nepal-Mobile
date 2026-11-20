from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ConversationCreate(BaseModel):
    """Open (or reuse) the thread with [recipient_id]."""

    recipient_id: int


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class PeerResponse(BaseModel):
    """The counterpart account as this viewer sees it (camelCase name
    fields match `GET /profile/me` and the mobile `AppUser` parser)."""

    id: int
    firstName: Optional[str] = None
    lastName: Optional[str] = None
    avatarUrl: Optional[str] = None
    role: str = "traveler"


class LastMessageResponse(BaseModel):
    id: int
    body: str
    sender_id: int
    created_at: datetime


class ConversationResponse(BaseModel):
    id: int
    peer: PeerResponse
    last_message: Optional[LastMessageResponse] = None
    unread_count: int = 0
    created_at: datetime


class MessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    body: str
    created_at: datetime
    read_at: Optional[datetime] = None

    class Config:
        from_attributes = True
