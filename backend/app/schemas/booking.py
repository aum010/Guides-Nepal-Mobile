from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum


class BookingStatus(str, Enum):
    upcoming = "upcoming"
    accepted = "accepted"
    rejected = "rejected"
    completed = "completed"
    cancelled = "cancelled"
    archived = "archived"


class BookingBase(BaseModel):
    experience_id: int
    experience_title: str
    city: str
    date: datetime
    # Bounded because guests now move a listing's seat count: a negative or
    # zero value would release seats nobody held.
    guests: int = Field(ge=1, le=100)
    price: float = Field(ge=0)
    image: Optional[str] = None


class BookingCreate(BookingBase):
    pass


class BookingUpdate(BaseModel):
    status: Optional[BookingStatus] = None


class BookingResponse(BookingBase):
    id: int
    user_id: int
    # Assigned guide account — the mobile app uses this as the "Message
    # guide" entry point into the conversations API. Null until assigned.
    guide_user_id: Optional[int] = None
    guide_name: Optional[str] = None
    # Set when the booking came from a published guide listing.
    guide_listing_id: Optional[int] = None
    status: BookingStatus
    created_at: datetime

    class Config:
        from_attributes = True
