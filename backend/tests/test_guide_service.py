"""Unit tests for GuideService: creation, the active-only listing with its
city filter, updates, and the soft-delete path the public directory relies
on."""

from typing import Any
from sqlalchemy.orm import Session

from app.schemas.public import GuideCreate, GuideUpdate
from app.services.guide_service import GuideService


def _payload(**overrides: Any) -> GuideCreate:
    fields = dict(
        name="Mingma Gelu",
        image="https://example.com/gel.jpg",
        role="Trekking guide",
        rating=4.7,
        reviews=21,
        bio="Annapurna and Manaslu specialist.",
        languages=["Nepali", "English"],
        cities=["Pokhara", "Jomsom"],
    )
    fields.update(overrides)
    return GuideCreate(**fields)


def test_create_and_fetch_round_trip(db_session: Session) -> None:
    service = GuideService(db_session)
    created = service.create_guide(_payload())
    assert created.id is not None

    fetched = service.get_guide(created.id)
    assert fetched is not None
    assert fetched.name == "Mingma Gelu"
    assert service.get_guide(999999) is None


def test_listing_hides_inactive_guides_and_filters_by_city(db_session: Session) -> None:
    service = GuideService(db_session)
    pokhara = service.create_guide(_payload())
    service.create_guide(_payload(name="Kathmandu Only", cities=["Kathmandu"]))
    retired = service.create_guide(_payload(name="Retired Guide"))
    service.delete_guide(retired.id)

    all_active = service.get_all_guides()
    assert {g.id for g in all_active} == {g.id for g in all_active if g.is_active}
    assert pokhara.id in {g.id for g in all_active}
    assert retired.id not in {g.id for g in all_active}

    only_pokhara = service.get_all_guides(city="Pokhara")
    assert {g.id for g in only_pokhara} == {pokhara.id}


def test_update_applies_fields_and_returns_none_for_missing(
    db_session: Session,
) -> None:
    service = GuideService(db_session)
    guide = service.create_guide(_payload())

    updated = service.update_guide(
        guide.id, GuideUpdate(name="Geluru Sherpa", rating=5.0, is_active=True)
    )
    assert updated is not None
    assert updated.name == "Geluru Sherpa"
    assert updated.rating == 5.0

    assert service.update_guide(999999, GuideUpdate(name="Ghost")) is None


def test_delete_is_a_soft_delete_and_reports_missing_targets(
    db_session: Session,
) -> None:
    service = GuideService(db_session)
    guide = service.create_guide(_payload())

    assert service.delete_guide(guide.id) is True
    assert service.get_guide(guide.id) is None
    assert service.delete_guide(999999) is False
