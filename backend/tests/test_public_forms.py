"""Public website endpoints: contact/application forms, the host signup
wizard, the experience browser (filters/sorts/detail), and the guide
directory."""

import json
import os

from fastapi.testclient import TestClient

from app.api.v1.public import MOCK_EXPERIENCES
from app.core.security import get_password_hash
from typing import Any
from sqlalchemy.orm import Session
from app.models.booking import HostExperience
from app.models.guide import Guide
from app.models.host_application import HostApplication
from app.models.support_ticket import SupportTicket
from app.models.user import User

PUBLIC = "/api/v1"

UPLOAD_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "../app/private_host_applications")
)

# 1x1 transparent PNG.
PNG_BYTES = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000d49444154789c6360000002000100ffff03000006000557bfabd400"
    "00000049454e44ae426082"
)


def _guide(
    db: Session, name: str, cities: Any, verified: bool = False, active: bool = True
) -> Guide:
    guide = Guide(
        name=name,
        image="https://example.com/g.jpg",
        role="Mountain guide",
        rating=4.5,
        reviews=10,
        bio="Local guide sharing mountain stories.",
        languages=["Nepali", "English"],
        cities=list(cities),
        gallery=[],
        verified=verified,
        is_active=active,
    )
    db.add(guide)
    db.commit()
    db.refresh(guide)
    return guide


def _publish_experience(db: Session, host: Any, **fields: Any) -> HostExperience:
    """Create a host experience that surfaces publicly: live rows only
    appear once an active catalog guide is assigned to them."""
    from app.models.host_guide import HostExperienceGuide

    experience = HostExperience(host_id=host.id, **fields)
    db.add(experience)
    db.commit()
    db.refresh(experience)
    guide = _guide(db, f"Assigned Guide {experience.id}", [experience.city])
    assignment = HostExperienceGuide(
        host_id=host.id,
        experience_id=experience.id,
        guide_id=guide.id,
        is_primary=True,
    )
    db.add(assignment)
    db.commit()
    return experience


class TestInquiryForm:
    def test_inquiry_is_stored_as_a_support_ticket(
        self, client: TestClient, db_session: Session
    ) -> None:
        response = client.post(
            f"{PUBLIC}/inquiries",
            json={
                "name": "Curious Trekker",
                "email": "curious@example.com",
                "subject": "Group booking question",
                "message": "Do you offer discounts for groups of eight?",
                "category": "bookings",
            },
        )
        assert response.status_code == 201, response.text
        assert response.json()["status"] == "ok"

        ticket = db_session.query(SupportTicket).one()
        assert ticket.subject == "[bookings] Group booking question"
        assert ticket.customer_email == "curious@example.com"
        assert ticket.status == "open"

    def test_default_category_is_general(
        self, client: TestClient, db_session: Session
    ) -> None:
        response = client.post(
            f"{PUBLIC}/inquiries",
            json={
                "name": "Ana",
                "email": "ana@example.com",
                "subject": "Hello",
                "message": "Just saying hi.",
            },
        )
        assert response.status_code == 201, response.text
        ticket = db_session.query(SupportTicket).one()
        assert (ticket.subject or "").startswith("[general]")


class TestApplicationForms:
    def test_host_application_is_recorded_as_pending(
        self, client: TestClient, db_session: Session
    ) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications",
            json={
                "full_name": "Prakash Thapa",
                "email": "prakash@example.com",
                "phone": "9800000000",
                "city": "Pokhara",
                "documents": "citizenship.pdf",
            },
        )
        assert response.status_code == 201, response.text
        application = db_session.query(HostApplication).one()
        assert application.status == "pending"
        assert application.email == "prakash@example.com"
        assert application.host_name == "Prakash Thapa"

    def test_guide_application_lands_in_the_guide_funnel(
        self, client: TestClient, db_session: Session
    ) -> None:
        from app.models.guide_application import GuideApplication

        response = client.post(
            f"{PUBLIC}/guide-applications",
            json={
                "full_name": "Nima Sherpa",
                "email": "nima@example.com",
                "city": "Namche",
                "nin_number": "1234567890",
            },
        )
        assert response.status_code == 201, response.text
        application = db_session.query(GuideApplication).one()
        assert application.status == "pending"
        assert application.full_name == "Nima Sherpa"
        # The host funnel must stay empty.
        assert db_session.query(HostApplication).count() == 0


class TestHostApplicationWizard:
    def _form(self, **overrides: Any) -> dict:
        form = {
            "first_name": "Sabina",
            "last_name": "Karki",
            "date_of_birth": "1994-04-12",
            "nationality": "Nepali",
            "email": "sabina@example.com",
            "phone": "9811111111",
            "address": "Lakeside Road 12",
            "city": "Pokhara",
            "district": "Kaski",
            "languages": "Nepali,English",
            "host_type": "individual",
            "primary_city": "Pokhara",
            "years_experience": "6",
            "expertise": "Kayaking and paragliding logistics",
            "experience": (
                "I have coordinated logistics for lake and hill activities for "
                "six seasons, working with certified operators every step."
            ),
            "proposedTitle": "Phewa Lake Kayak Morning",
            "proposedDescription": "A calm morning paddle with a safety briefing.",
            "proposedCategory": "adventure",
            "proposedDuration": "3 hours",
            "price": "35",
            "availability": "Daily except monsoon",
            "password": "StrongPass1!",
            "terms": True,
            "privacy": True,
            "accuracy": True,
        }
        form.update(overrides)
        return form

    def test_missing_required_field_is_rejected(self, client: TestClient) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(first_name=""),
        )
        assert response.status_code == 422

    def test_declarations_must_be_accepted(self, client: TestClient) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(terms=False),
        )
        assert response.status_code == 422
        assert "declarations" in response.json()["detail"]

    def test_thin_experience_sections_are_rejected(self, client: TestClient) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(experience="Too short.", proposedDescription="Also short."),
        )
        assert response.status_code == 422
        assert "more detail" in response.json()["detail"]

    def test_weak_password_is_rejected(self, client: TestClient) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(password="weak"),
        )
        assert response.status_code == 422
        assert "Password" in response.json()["detail"]

    def test_disallowed_file_types_are_rejected_without_writing(
        self, client: TestClient
    ) -> None:
        before = set(os.listdir(UPLOAD_ROOT)) if os.path.isdir(UPLOAD_ROOT) else set()
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(),
            files={"identity": ("id.txt", b"not an image", "text/plain")},
        )
        assert response.status_code == 422
        assert "identity" in response.json()["detail"]
        after = set(os.listdir(UPLOAD_ROOT)) if os.path.isdir(UPLOAD_ROOT) else set()
        assert after == before

    def test_valid_wizard_submission_mints_a_pending_application(
        self, client: TestClient, db_session: Session
    ) -> None:
        response = client.post(
            f"{PUBLIC}/host-applications/submit",
            data=self._form(),
            files={"photo": ("passport.png", PNG_BYTES, "image/png")},
        )
        assert response.status_code == 201, response.text
        application_id = response.json()["id"]

        application = (
            db_session.query(HostApplication)
            .filter(HostApplication.id == application_id)
            .one()
        )
        assert application.status == "pending"
        assert application.credential_password_hash
        assert application.credential_password_hash != "StrongPass1!"

        assert application.experience is not None
        details = json.loads(application.experience)
        assert details["proposed_experience"]["title"] == "Phewa Lake Kayak Morning"
        stored_files = details["documents"]
        try:
            assert "photo" in stored_files
            stored_path = os.path.join(UPLOAD_ROOT, stored_files["photo"])
            assert os.path.exists(stored_path)
            with open(stored_path, "rb") as handle:
                assert handle.read() == PNG_BYTES
        finally:
            for filename in stored_files.values():
                path = os.path.join(UPLOAD_ROOT, filename)
                if os.path.exists(path):
                    os.remove(path)


class TestExperienceBrowser:
    def test_city_category_and_search_filters(
        self, client: TestClient, db_session: Session
    ) -> None:
        # A live host experience surfaces alongside the mocks.
        host = User(
            email="browser-host@example.com",
            firstName="Bikash",
            lastName="Host",
            hashed_password=get_password_hash("TestPassword123!"),
            role="host",
            is_active=True,
        )
        db_session.add(host)
        db_session.commit()
        _publish_experience(
            db_session,
            host,
            title="Sunset Canoe on the Lake",
            slug="sunset-canoe",
            city="Pokhara",
            category="adventure",
            description="A gentle evening paddle as the sun drops behind Machhapuchhre.",
            price=40.0,
            duration="2 hours",
            is_active=True,
        )

        everything = client.get(f"{PUBLIC}/experiences")
        assert everything.status_code == 200, everything.text
        titles = {row["title"] for row in everything.json()}
        assert "Sunset Canoe on the Lake" in titles
        assert len(everything.json()) >= len(MOCK_EXPERIENCES)

        first_city = MOCK_EXPERIENCES[0]["city"]
        by_city = client.get(
            f"{PUBLIC}/experiences", params={"city": first_city.upper()}
        )
        assert by_city.status_code == 200
        assert {row["city"] for row in by_city.json()} == {first_city}

        by_category = client.get(
            f"{PUBLIC}/experiences",
            params={"category": MOCK_EXPERIENCES[0]["category"]},
        )
        assert by_category.status_code == 200
        assert {row["category"].lower() for row in by_category.json()} == {
            MOCK_EXPERIENCES[0]["category"].lower()
        }

        needle = MOCK_EXPERIENCES[0]["title"].split()[0]
        by_search = client.get(f"{PUBLIC}/experiences", params={"search": needle})
        assert by_search.status_code == 200
        assert by_search.json()

    def test_price_range_and_sorting(self, client: TestClient) -> None:
        cheap = client.get(f"{PUBLIC}/experiences", params={"max_price": 50})
        assert cheap.status_code == 200
        assert all(row["price"] <= 50 for row in cheap.json())

        pricy = client.get(f"{PUBLIC}/experiences", params={"min_price": 60})
        assert pricy.status_code == 200
        assert all(row["price"] >= 60 for row in pricy.json())

        for sort in ("price_low", "price_high", "rating", "popular"):
            response = client.get(f"{PUBLIC}/experiences", params={"sort": sort})
            assert response.status_code == 200, f"{sort}: {response.text}"
            assert response.json()

        ascending = client.get(
            f"{PUBLIC}/experiences", params={"sort": "price_low"}
        ).json()
        prices = [row["price"] for row in ascending]
        assert prices == sorted(prices)

        descending = client.get(
            f"{PUBLIC}/experiences", params={"sort": "price_high"}
        ).json()
        assert [row["price"] for row in descending] == sorted(prices, reverse=True)

    def test_detail_lookup_for_mock_host_and_unknown_slugs(
        self, client: TestClient
    ) -> None:
        mock = MOCK_EXPERIENCES[0]
        found = client.get(f"{PUBLIC}/experiences/{mock['slug']}")
        assert found.status_code == 200, found.text
        assert found.json()["slug"] == mock["slug"]

        missing = client.get(f"{PUBLIC}/experiences/no-such-slug")
        assert missing.status_code == 404

    def test_detail_lookup_for_a_live_host_experience(
        self, client: TestClient, db_session: Session
    ) -> None:

        host = User(
            email="detail-host@example.com",
            firstName="Tara",
            lastName="Host",
            hashed_password=get_password_hash("TestPassword123!"),
            role="host",
            is_active=True,
        )
        db_session.add(host)
        db_session.commit()
        _publish_experience(
            db_session,
            host,
            title="Mardi Base Camp Day Hike",
            slug="mardi-base-camp",
            city="Pokhara",
            category="trekking",
            description="Drive to Kande and hike toward the Mardi Himal viewpoints.",
            price=70.0,
            duration="Full day",
            is_active=True,
        )

        found = client.get(f"{PUBLIC}/experiences/host-mardi-base-camp")
        assert found.status_code == 200, found.text
        assert found.json()["slug"] == "host-mardi-base-camp"
        assert found.json()["title"] == "Mardi Base Camp Day Hike"

        absent = client.get(f"{PUBLIC}/experiences/host-not-there")
        assert absent.status_code == 404


class TestGuideDirectory:
    def test_guides_are_listed_and_detail_fetch_works(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _guide(db_session, "Pemba Dorje", ["Pokhara"])
        _guide(db_session, "Inactive Guide", ["Kathmandu"], active=False)

        listing = client.get(f"{PUBLIC}/guides")
        assert listing.status_code == 200, listing.text
        names = {row["name"] for row in listing.json()}
        assert names == {"Pemba Dorje"}  # inactive guides stay hidden

        detail = client.get(f"{PUBLIC}/guides/{guide.id}")
        assert detail.status_code == 200, detail.text
        assert detail.json()["name"] == "Pemba Dorje"

    def test_unknown_guide_is_404(self, client: TestClient) -> None:
        assert client.get(f"{PUBLIC}/guides/999999").status_code == 404
