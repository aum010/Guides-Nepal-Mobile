"""Reviews API: traveller-only guardrails around who may review what.

Covers the public list, the traveller-only identity routes, and the
create/update/delete rules (completed booking required, one review per
traveller per experience, own-review-only edits).
"""

from typing import Any
from sqlalchemy.orm import Session
from datetime import datetime

from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.booking import Booking, BookingStatus
from app.models.review import Review
from app.models.user import User

REVIEWS = "/api/v1/reviews"
EXPERIENCE = 7


def _register(client: TestClient, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPassword123!",
            "firstName": "Tara",
            "lastName": email.split("@")[0].title(),
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _traveler_id(client: TestClient, headers: dict) -> int:
    me = client.get("/api/v1/profile/me", headers=headers)
    assert me.status_code == 200, me.text
    return int(me.json()["id"])


def _staff(db: Session, email: str, role: str) -> User:
    user = User(
        email=email,
        firstName="Dawa",
        lastName="Guide",
        hashed_password=get_password_hash("TestPassword123!"),
        role=role,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _completed_booking(
    db: Session, user_id: int, experience_id: int = EXPERIENCE
) -> Booking:
    booking = Booking(
        user_id=user_id,
        experience_id=experience_id,
        experience_title="Sunrise over Sarangkot",
        city="Pokhara",
        date=datetime(2026, 11, 2),
        guests=2,
        price=200.0,
        status=BookingStatus.completed,
    )
    db.add(booking)
    db.commit()
    return booking


class TestListReviews:
    def test_listing_is_public_and_scoped_to_the_experience(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _register(client, "list-review@example.com")
        traveler_id = _traveler_id(client, traveler)
        db_session.add(
            Review(
                experience_id=EXPERIENCE, user_id=traveler_id, rating=5, comment="Magic"
            )
        )
        db_session.add(
            Review(experience_id=999, user_id=traveler_id, rating=1, comment="Other")
        )
        db_session.commit()

        response = client.get(f"{REVIEWS}/", params={"experience_id": EXPERIENCE})
        assert response.status_code == 200, response.text
        rows = response.json()
        assert len(rows) == 1
        assert rows[0]["comment"] == "Magic"

    def test_listing_an_unknown_experience_returns_empty(
        self, client: TestClient
    ) -> None:
        response = client.get(f"{REVIEWS}/", params={"experience_id": 4242})
        assert response.status_code == 200
        assert response.json() == []


class TestMyReviews:
    def test_returns_only_your_own_reviews(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _register(client, "mine-review@example.com")
        user_id = _traveler_id(client, headers)
        other = _staff(db_session, "other-reviewer@example.com", "traveler")
        db_session.add(
            Review(experience_id=1, user_id=user_id, rating=4, comment="mine")
        )
        db_session.add(
            Review(experience_id=2, user_id=other.id, rating=2, comment="theirs")
        )
        db_session.commit()

        response = client.get(f"{REVIEWS}/me", headers=headers)
        assert response.status_code == 200, response.text
        rows = response.json()
        assert [row["comment"] for row in rows] == ["mine"]

    def test_requires_authentication(self, client: TestClient) -> None:
        assert client.get(f"{REVIEWS}/me").status_code == 401

    def test_rejects_non_travellers(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _staff(db_session, "guide-review@example.com", "guide")
        response = client.get(f"{REVIEWS}/me", headers=_bearer(guide))
        assert response.status_code == 403


class TestCanReview:
    def test_needs_a_completed_booking(self, client: TestClient) -> None:
        headers = _register(client, "canreview-new@example.com")
        response = client.get(
            f"{REVIEWS}/can-review",
            params={"experience_id": EXPERIENCE},
            headers=headers,
        )
        assert response.status_code == 200
        assert response.json()["can_review"] is False
        assert "taken" in response.json()["reason"]

    def test_allows_after_a_completed_booking(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _register(client, "canreview-ok@example.com")
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)

        response = client.get(
            f"{REVIEWS}/can-review",
            params={"experience_id": EXPERIENCE},
            headers=headers,
        )
        assert response.status_code == 200
        assert response.json() == {"can_review": True, "reason": None}

    def test_blocks_a_second_review_of_the_same_experience(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _register(client, "canreview-twice@example.com")
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)
        db_session.add(
            Review(experience_id=EXPERIENCE, user_id=user_id, rating=5, comment="done")
        )
        db_session.commit()

        response = client.get(
            f"{REVIEWS}/can-review",
            params={"experience_id": EXPERIENCE},
            headers=headers,
        )
        assert response.status_code == 200
        assert response.json()["can_review"] is False
        assert "already" in response.json()["reason"]

    def test_rejects_non_travellers(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _staff(db_session, "guide-canreview@example.com", "guide")
        response = client.get(
            f"{REVIEWS}/can-review",
            params={"experience_id": EXPERIENCE},
            headers=_bearer(guide),
        )
        assert response.status_code == 403


class TestCreateReview:
    def _payload(self, **overrides: Any) -> dict:
        payload = {
            "experience_id": EXPERIENCE,
            "rating": 5,
            "comment": "Incredible views",
        }
        payload.update(overrides)
        return payload

    def test_happy_path_returns_201(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _register(client, "create-review@example.com")
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)

        response = client.post(f"{REVIEWS}/", json=self._payload(), headers=headers)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["rating"] == 5
        assert body["user_id"] == user_id

    def test_requires_authentication(self, client: TestClient) -> None:
        assert client.post(f"{REVIEWS}/", json=self._payload()).status_code == 401

    def test_rejects_non_travellers(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _staff(db_session, "guide-create@example.com", "guide")
        response = client.post(
            f"{REVIEWS}/", json=self._payload(), headers=_bearer(guide)
        )
        assert response.status_code == 403

    def test_rejects_without_a_completed_booking(self, client: TestClient) -> None:
        headers = _register(client, "create-nobook@example.com")
        response = client.post(f"{REVIEWS}/", json=self._payload(), headers=headers)
        assert response.status_code == 403

    def test_rejects_a_duplicate_review(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _register(client, "create-twice@example.com")
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)
        first = client.post(f"{REVIEWS}/", json=self._payload(), headers=headers)
        assert first.status_code == 201, first.text

        second = client.post(f"{REVIEWS}/", json=self._payload(), headers=headers)
        assert second.status_code == 409

    def test_rating_bounds_are_enforced_by_the_schema(self, client: TestClient) -> None:
        headers = _register(client, "create-bounds@example.com")
        for rating in (0, 6):
            response = client.post(
                f"{REVIEWS}/", json=self._payload(rating=rating), headers=headers
            )
            assert response.status_code == 422, response.text


class TestUpdateReview:
    def _own_review(
        self, client: TestClient, db_session: Session, email: str
    ) -> tuple[dict, int]:
        headers = _register(client, email)
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)
        created = client.post(
            f"{REVIEWS}/",
            json={"experience_id": EXPERIENCE, "rating": 3, "comment": "Fine"},
            headers=headers,
        )
        assert created.status_code == 201, created.text
        return headers, created.json()["id"]

    def test_owner_can_change_rating_and_comment(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers, review_id = self._own_review(
            client, db_session, "update-own@example.com"
        )
        response = client.put(
            f"{REVIEWS}/{review_id}",
            json={"rating": 5, "comment": "Actually stunning"},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        assert response.json()["rating"] == 5
        assert response.json()["comment"] == "Actually stunning"

    def test_partial_update_leaves_other_fields_alone(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers, review_id = self._own_review(
            client, db_session, "update-partial@example.com"
        )
        response = client.put(
            f"{REVIEWS}/{review_id}", json={"comment": "Updated text"}, headers=headers
        )
        assert response.status_code == 200, response.text
        assert response.json()["comment"] == "Updated text"
        assert response.json()["rating"] == 3

    def test_foreign_reviews_are_locked(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers, review_id = self._own_review(
            client, db_session, "update-owner@example.com"
        )
        stranger = _staff(db_session, "update-stranger@example.com", "traveler")
        response = client.put(
            f"{REVIEWS}/{review_id}", json={"rating": 1}, headers=_bearer(stranger)
        )
        assert response.status_code == 403

    def test_unknown_review_is_404(self, client: TestClient) -> None:
        headers = _register(client, "update-missing@example.com")
        response = client.put(f"{REVIEWS}/999999", json={"rating": 4}, headers=headers)
        assert response.status_code == 404

    def test_non_travellers_cannot_edit(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _staff(db_session, "guide-update@example.com", "guide")
        response = client.put(
            f"{REVIEWS}/1", json={"rating": 4}, headers=_bearer(guide)
        )
        assert response.status_code == 403


class TestDeleteReview:
    def _own_review(
        self, client: TestClient, db_session: Session, email: str
    ) -> tuple[dict, int]:
        headers = _register(client, email)
        user_id = _traveler_id(client, headers)
        _completed_booking(db_session, user_id)
        created = client.post(
            f"{REVIEWS}/",
            json={"experience_id": EXPERIENCE, "rating": 4, "comment": "Loved it"},
            headers=headers,
        )
        assert created.status_code == 201, created.text
        return headers, created.json()["id"]

    def test_owner_can_delete_their_review(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers, review_id = self._own_review(
            client, db_session, "delete-own@example.com"
        )
        response = client.delete(f"{REVIEWS}/{review_id}", headers=headers)
        assert response.status_code == 204, response.text

        mine = client.get(f"{REVIEWS}/me", headers=headers)
        assert mine.json() == []

    def test_foreign_reviews_cannot_be_deleted(
        self, client: TestClient, db_session: Session
    ) -> None:
        _, review_id = self._own_review(client, db_session, "delete-owner@example.com")
        stranger = _staff(db_session, "delete-stranger@example.com", "traveler")
        response = client.delete(f"{REVIEWS}/{review_id}", headers=_bearer(stranger))
        assert response.status_code == 403

    def test_unknown_review_is_404(self, client: TestClient) -> None:
        headers = _register(client, "delete-missing@example.com")
        assert client.delete(f"{REVIEWS}/999999", headers=headers).status_code == 404

    def test_non_travellers_cannot_delete(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _staff(db_session, "guide-delete@example.com", "guide")
        assert client.delete(f"{REVIEWS}/1", headers=_bearer(guide)).status_code == 403
