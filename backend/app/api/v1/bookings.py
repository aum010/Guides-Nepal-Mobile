from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.core.database import get_db
from app.schemas.booking import BookingCreate, BookingResponse
from app.services.booking_service import BookingService
from app.models.booking import Booking
from app.core.dependencies import get_current_user
from app.models.user import User

router = APIRouter()


@router.get("/availability")
def booking_availability(
    date: str = Query(pattern=r"^\d{4}-\d{2}-\d{2}$"),
    experience_id: Optional[int] = Query(
        default=None,
        description="Catalogue row being booked; publishes seats for a guide listing.",
    ),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict:
    """Availability for a calendar date.

    Without ``experience_id`` this answers for the fallback catalogue guide
    (the seeded content has no specific guide). With it, a published listing is
    answered for the guide who owns it plus that listing's remaining seats.
    """
    return BookingService(db).availability_for_date(date, experience_id)


@router.get("/", response_model=List[BookingResponse])
def get_bookings(
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user)
) -> List[Booking]:
    service = BookingService(db)
    return service.get_user_bookings(current_user.id)


@router.post("/", response_model=BookingResponse)
def create_booking(
    booking_in: BookingCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Booking:
    service = BookingService(db)
    return service.create_booking(current_user.id, booking_in)


@router.post("/{id}/cancel", response_model=BookingResponse)
def cancel_booking(
    id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Booking:
    service = BookingService(db)
    booking = service.cancel_booking(current_user.id, id)
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    return booking


@router.post("/{id}/archive", response_model=BookingResponse)
def archive_booking(
    id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Booking:
    service = BookingService(db)
    booking = service.archive_booking(current_user.id, id)
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    return booking
