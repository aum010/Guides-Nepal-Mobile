"""Tests for the traveller-facing guide updates feed (`GET /api/v1/updates`).

The feed is the only public surface for ``guide_status_updates``. Two
properties matter and are covered here:

- **Visibility** — an update is reachable only while it is active, current
  (not stale, not past its event day), not an internal ``booking`` note, and
  attached to a city a traveller could actually be browsing.
- **Privacy** — the payload carries the guide's chosen display name and the
  update text, and nothing else identifying: no ``guide_user_id``, no
  ``listing_id``, no email, no traveller details.
"""

from datetime import datetime, timedelta

from app.core.security import get_password_hash
from app.models.guide_listing import GuideListing, GuideProfile, GuideStatusUpdate
from app.models.user import User

BASE = "/api/v1/updates"


def _make_guide(db_session, email: str, **profile) -> User:
    user = User(
        email=email,
        hashed_password=get_password_hash("Guide@2024"),
        firstName=email.split("@")[0].title(),
        lastName="Sherpa",
        role="guide",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    if profile:
        db_session.add(GuideProfile(guide_user_id=user.id, **profile))
        db_session.commit()
    return user


def _make_listing(db_session, guide: User, **overrides) -> GuideListing:
    defaults = {
        "guide_user_id": guide.id,
        "title": "Sunrise hike to Sarangkot",
        "category": "trekking",
        "city": "Pokhara",
        "description": "An easy pre-dawn walk to the ridge above the lake.",
        "duration": "4 hours",
        "difficulty": "Moderate",
        "price": 45.0,
        "max_guests": 8,
        "is_active": True,
    }
    defaults.update(overrides)
    listing = GuideListing(**defaults)
    db_session.add(listing)
    db_session.commit()
    db_session.refresh(listing)
    return listing


def _make_update(db_session, guide: User, **overrides) -> GuideStatusUpdate:
    defaults = {
        "guide_user_id": guide.id,
        "update_type": "announcement",
        "message": "Lakeside pickup moves to the clock tower.",
        "is_active": True,
        "created_at": datetime.now(),
    }
    defaults.update(overrides)
    update = GuideStatusUpdate(**defaults)
    db_session.add(update)
    db_session.commit()
    db_session.refresh(update)
    return update


class TestVisibility:
    def test_active_update_reaches_the_city_the_guide_declared(
        self, client, db_session
    ):
        guide = _make_guide(
            db_session,
            "pemba@example.com",
            display_name="Pemba Sherpa",
            cities=["Pokhara", "Kathmandu"],
        )
        _make_update(db_session, guide)

        payload = client.get(f"{BASE}?city=Pokhara").json()

        assert [u["message"] for u in payload] == [
            "Lakeside pickup moves to the clock tower."
        ]
        assert payload[0]["guide_name"] == "Pemba Sherpa"

    def test_city_match_ignores_case_and_padding(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(db_session, guide)

        assert client.get(f"{BASE}?city=pOkHaRa").json() != []
        assert client.get(f"{BASE}?city=%20Pokhara%20").json() != []

    def test_another_city_does_not_see_the_update(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(db_session, guide)

        assert client.get(f"{BASE}?city=Bhaktapur").json() == []

    def test_guide_without_a_profile_cannot_be_placed_in_a_city(
        self, client, db_session
    ):
        """A guide who never onboarded has no cities, so their guide-wide
        update has nowhere public to surface — it stays workspace-only."""
        guide = _make_guide(db_session, "silent@example.com")
        _make_update(db_session, guide)

        assert client.get(f"{BASE}?city=Pokhara").json() == []

    def test_update_attached_to_a_listing_uses_the_listing_city(
        self, client, db_session
    ):
        """The listing's city wins, so a guide's other cities do not pick up
        an update that is really about one specific listing."""
        guide = _make_guide(db_session, "pemba@example.com", cities=["Kathmandu"])
        listing = _make_listing(db_session, guide, city="Pokhara")
        _make_update(db_session, guide, listing_id=listing.id)

        assert client.get(f"{BASE}?city=Pokhara").json() != []
        assert client.get(f"{BASE}?city=Kathmandu").json() == []

    def test_update_for_a_paused_listing_is_hidden(self, client, db_session):
        """Pausing a listing hides it from travellers, so its updates stop
        being public too rather than outliving the listing."""
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        listing = _make_listing(db_session, guide, is_active=False)
        _make_update(db_session, guide, listing_id=listing.id)

        assert client.get(f"{BASE}?city=Pokhara").json() == []

    def test_stale_undated_update_drops_out_of_the_feed(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(
            db_session,
            guide,
            created_at=datetime.now() - timedelta(days=40),
        )

        assert client.get(f"{BASE}?city=Pokhara").json() == []

    def test_dated_update_is_kept_through_its_day_then_drops(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        tomorrow = today + timedelta(days=1)

        _make_update(
            db_session,
            guide,
            update_type="schedule",
            message="Sunrise start moves to 5:30 am.",
            event_date=tomorrow,
        )
        assert client.get(f"{BASE}?city=Pokhara").json() != []

        _make_update(
            db_session,
            guide,
            update_type="schedule",
            message="This one already happened.",
            event_date=today - timedelta(days=1),
        )
        messages = [u["message"] for u in client.get(f"{BASE}?city=Pokhara").json()]
        assert messages == ["Sunrise start moves to 5:30 am."]

    def test_booking_notes_never_become_public(self, client, db_session):
        """`booking` updates are written for the guide's own workflow about
        one reservation, so they are never part of a traveller feed."""
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(
            db_session,
            guide,
            update_type="booking",
            message="Group of 4 confirmed for Saturday.",
        )
        _make_update(
            db_session, guide, update_type="capacity", message="Two spots left."
        )

        messages = [u["message"] for u in client.get(f"{BASE}?city=Pokhara").json()]
        assert messages == ["Two spots left."]

    def test_guide_can_hide_an_update_without_deleting_it(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(db_session, guide, is_active=False)

        assert client.get(f"{BASE}?city=Pokhara").json() == []

    def test_without_a_city_filter_every_current_update_returns(
        self, client, db_session
    ):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        second = _make_guide(db_session, "aarati@example.com", cities=["Bhaktapur"])
        _make_update(db_session, guide, message="First update.")
        _make_update(db_session, second, message="Second update.")

        assert len(client.get(BASE).json()) == 2

    def test_limit_truncates_the_visible_feed(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        for index in range(5):
            _make_update(db_session, guide, message=f"Update number {index}.")

        payload = client.get(f"{BASE}?city=Pokhara&limit=2").json()

        assert len(payload) == 2
        # Newest first.
        assert payload[0]["message"] == "Update number 4."


class TestPrivacy:
    def test_payload_exposes_no_internal_identifiers(self, client, db_session):
        guide = _make_guide(
            db_session,
            "pemba@example.com",
            display_name="Pemba Sherpa",
            cities=["Pokhara"],
        )
        listing = _make_listing(db_session, guide)
        _make_update(db_session, guide, listing_id=listing.id)

        row = client.get(f"{BASE}?city=Pokhara").json()[0]

        assert set(row) == {
            "id",
            "update_type",
            "message",
            "area",
            "event_date",
            "current_capacity",
            "max_capacity",
            "created_at",
            "guide_name",
            "listing_title",
            "cities",
        }
        assert "guide_user_id" not in row
        assert "listing_id" not in row

    def test_guide_name_falls_back_to_the_account_name(self, client, db_session):
        """No onboarding display name means the account's own name, then a
        neutral label — never an email address."""
        guide = _make_guide(db_session, "nohandle@example.com")
        _make_update(db_session, guide)

        assert client.get(f"{BASE}?city=Kathmandu").json() == []

        # Give the guide a city via a listing so the update is reachable.
        listing = _make_listing(db_session, guide, city="Kathmandu")
        _make_update(db_session, guide, listing_id=listing.id)

        row = client.get(f"{BASE}?city=Kathmandu").json()[0]
        assert row["guide_name"] == "Nohandle Sherpa"
        assert "nohandle@example.com" not in str(row)

    def test_guide_name_never_falls_back_to_an_email(self, client, db_session):
        guide = _make_guide(db_session, "nohandle@example.com")
        listing = _make_listing(db_session, guide, city="Kathmandu")
        _make_update(
            db_session,
            guide,
            listing_id=listing.id,
            message="A guide with no name at all.",
        )

        row = client.get(f"{BASE}?city=Kathmandu").json()[0]
        assert row["guide_name"] != "A local guide"  # account name exists
        assert "@" not in row["guide_name"]

    def test_feed_never_leaks_details_of_an_unrelated_booking(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(db_session, guide, message="Two spots left on Saturday.")

        blob = str(client.get(f"{BASE}?city=Pokhara").json())
        assert "guide_user_id" not in blob
        assert "hashed_password" not in blob


class TestResponseShape:
    def test_capacity_fields_surface_for_a_capacity_update(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        _make_update(
            db_session,
            guide,
            update_type="capacity",
            message="Only two spots left for Saturday.",
            area="Lakeside",
            current_capacity=6,
            max_capacity=8,
        )

        row = client.get(f"{BASE}?city=Pokhara").json()[0]

        assert row["update_type"] == "capacity"
        assert row["current_capacity"] == 6
        assert row["max_capacity"] == 8
        assert row["area"] == "Lakeside"
        assert row["listing_title"] is None

    def test_listing_title_resolves_for_a_linked_update(self, client, db_session):
        guide = _make_guide(db_session, "pemba@example.com", cities=["Pokhara"])
        listing = _make_listing(db_session, guide, title="Newari food walk")
        _make_update(db_session, guide, listing_id=listing.id, message="Moved to 5 pm.")

        row = client.get(f"{BASE}?city=Pokhara").json()[0]

        assert row["listing_title"] == "Newari food walk"
        assert row["cities"] == ["Pokhara"]

    def test_guide_wide_update_reports_every_declared_city(self, client, db_session):
        """A guide-wide note spans all the cities the guide works in, so the
        feed carries every one rather than an arbitrary first pick."""
        guide = _make_guide(
            db_session,
            "pemba@example.com",
            cities=["Pokhara", "Kathmandu"],
        )
        _make_update(db_session, guide, message="Season opens early this year.")

        row = client.get(f"{BASE}?city=Pokhara").json()[0]
        assert row["cities"] == ["Pokhara", "Kathmandu"]

    def test_blank_cities_are_dropped(self, client, db_session):
        guide = _make_guide(
            db_session,
            "pemba@example.com",
            cities=["Pokhara", "", "Pokhara", "Bhaktapur"],
        )
        _make_update(db_session, guide, message="Two spots left.")

        row = client.get(f"{BASE}?city=Pokhara").json()[0]
        assert row["cities"] == ["Pokhara", "Bhaktapur"]

    def test_feed_is_reachable_without_authentication(self, client, db_session):
        """The endpoint is traveller-facing, so no bearer token is required."""
        assert client.get(BASE).status_code == 200
