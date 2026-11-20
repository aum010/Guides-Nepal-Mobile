from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload
from app.models.booking import Booking, BookingStatus
from app.models.guide_listing import GuideListing
from app.models.user import User
from app.core.roles import GUIDE
from app.services.catalog_service import CatalogService
from fastapi import HTTPException
from app.schemas.booking import BookingCreate
from typing import List, Optional


class BookingService:
    def __init__(self, db: Session):
        self.db = db

    def get_user_bookings(self, user_id: int) -> List[Booking]:
        # Eager-load the assigned guide: `BookingResponse` serializes the
        # guide's display name and must not lazy-load after the session
        # dependency closes.
        return (
            self.db.query(Booking)
            .options(joinedload(Booking.guide))
            .filter(Booking.user_id == user_id)
            .all()
        )

    def get_booking_guide(self) -> User:
        """The single fallback guide for seeded catalogue content.

        Only rows that are not a published listing reach this: a guide listing
        is booked through the guide who owns it (see ``create_booking``).
        """
        guide = (
            self.db.query(User)
            .filter(
                User.email == "guide@guides-nepal.com",
                User.role == GUIDE,
                User.is_active.is_(True),
            )
            .first()
        )
        if not guide:
            raise HTTPException(
                status_code=503, detail="The booking guide is unavailable"
            )
        return guide

    def availability_for_date(
        self, date: str, experience_id: Optional[int] = None
    ) -> dict:
        """Whether one guide is free on [date], for this experience.

        Seeded content has no specific guide, so it is checked against the
        fallback catalogue guide's calendar. A published listing is checked
        against *its* guide's calendar **and** its own seat count, because a
        listing sells a fixed number of seats rather than one slot per day.
        """
        listing = (
            CatalogService(self.db).listing_for_experience(experience_id)
            if experience_id is not None
            else None
        )
        if listing is not None:
            guide = CatalogService(self.db).guide_for_listing(listing)
            spots_left = max(
                int(listing.max_guests or 0) - int(listing.booked_guests or 0), 0
            )
            if spots_left <= 0:
                return {"available": False, "status": "full", "spots_left": 0}
            day = self._day_state(guide.id, date)
            if day is not None:
                return {"available": False, "status": day, "spots_left": spots_left}
            return {"available": True, "status": "free", "spots_left": spots_left}

        guide = self.get_booking_guide()
        day = self._day_state(guide.id, date)
        if day is not None:
            return {"available": False, "status": day}
        return {"available": True, "status": "free"}

    def _day_state(self, guide_id: int, date: str) -> Optional[str]:
        """``booked`` / ``reserved`` when that guide already has this day."""
        active = (
            self.db.query(Booking)
            .filter(
                Booking.guide_user_id == guide_id,
                func.date(Booking.date) == date,
                Booking.status.in_([BookingStatus.upcoming, BookingStatus.accepted]),
            )
            .first()
        )
        if not active:
            return None
        return "booked" if active.status == BookingStatus.accepted else "reserved"

    def create_booking(self, user_id: int, booking_in: BookingCreate) -> Booking:
        catalog = CatalogService(self.db)
        listing = catalog.listing_for_experience(booking_in.experience_id)
        if listing is not None:
            return self._create_listing_booking(user_id, booking_in, listing)

        # Seeded catalogue content: one bookable guide account. Do not infer a
        # recipient from display-only guide profiles until those profiles have
        # their own authenticated accounts.
        guide = self.get_booking_guide()
        availability = self.availability_for_date(booking_in.date.date().isoformat())
        if not availability["available"]:
            raise HTTPException(
                status_code=409,
                detail=f"The guide is already {availability['status']} on this date. Please choose another date.",
            )
        db_booking = Booking(
            user_id=user_id,
            guide_user_id=guide.id,
            **booking_in.model_dump(),
        )
        self.db.add(db_booking)
        self.db.commit()
        self.db.refresh(db_booking)
        return db_booking

    def _create_listing_booking(
        self, user_id: int, booking_in: BookingCreate, listing: GuideListing
    ) -> Booking:
        """Book a seat on a published listing, held by its own guide."""
        guide = CatalogService(self.db).guide_for_listing(listing)
        if int(booking_in.guests) > int(listing.max_guests or 0):
            raise HTTPException(
                status_code=409,
                detail=f"This trip takes at most {listing.max_guests} guests.",
            )
        day_state = self._day_state(guide.id, booking_in.date.date().isoformat())
        if day_state is not None:
            raise HTTPException(
                status_code=409,
                detail=f"The guide is already {day_state} on this date. Please choose another date.",
            )

        # Reserve the seats in one guarded statement. Two travellers booking
        # the last seat at the same time cannot both succeed: the row-level
        # condition is re-evaluated by the database for each update.
        reserved = (
            self.db.query(GuideListing)
            .filter(
                GuideListing.id == listing.id,
                GuideListing.max_guests - GuideListing.booked_guests
                >= int(booking_in.guests),
            )
            .update(
                {
                    GuideListing.booked_guests: GuideListing.booked_guests
                    + int(booking_in.guests)
                },
                synchronize_session=False,
            )
        )
        if not reserved:
            self.db.rollback()
            raise HTTPException(
                status_code=409,
                detail="This trip is fully booked for those dates. Please pick another experience.",
            )

        db_booking = Booking(
            user_id=user_id,
            guide_user_id=guide.id,
            guide_listing_id=listing.id,
            **booking_in.model_dump(),
        )
        self.db.add(db_booking)
        self.db.commit()
        self.db.refresh(db_booking)
        return db_booking

    def release_capacity(self, booking: Booking) -> None:
        """Give a listing the seats a cancelled/rejected booking was holding.

        Safe to call twice — the booking's status is the guard — because
        cancelling, then the guide rejecting, must not free the seats twice.
        """
        if booking.guide_listing_id is None:
            return
        listing = self.db.get(GuideListing, booking.guide_listing_id)
        if listing is None:
            return
        listing.booked_guests = max(
            int(listing.booked_guests or 0) - int(booking.guests or 0), 0
        )

    def cancel_booking(self, user_id: int, booking_id: int) -> Optional[Booking]:
        booking = (
            self.db.query(Booking)
            .filter(Booking.id == booking_id, Booking.user_id == user_id)
            .first()
        )
        if booking:
            # A cancelled booking has already handed its seats back; only the
            # transition out of a live status releases them.
            if booking.status not in (BookingStatus.cancelled, BookingStatus.rejected):
                self.release_capacity(booking)
            booking.status = BookingStatus.cancelled
            self.db.commit()
            self.db.refresh(booking)
        return booking

    def archive_booking(self, user_id: int, booking_id: int) -> Optional[Booking]:
        booking = (
            self.db.query(Booking)
            .filter(Booking.id == booking_id, Booking.user_id == user_id)
            .first()
        )
        if booking:
            booking.status = BookingStatus.archived
            self.db.commit()
            self.db.refresh(booking)
        return booking
