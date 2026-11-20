"""Messaging endpoints (mobile/docs/api-gaps.md §2).

Covers the contract's four routes plus the guarantees the inbox UI leans
on: authentication, canonical get-or-create threads, participant-only
access (404 for outsiders), unread counts driven by the read side effect,
and the booking fields that give travelers their "Message guide" entry.
"""

from sqlalchemy.orm import Session

from datetime import datetime

from fastapi.testclient import TestClient

from typing import Any

from app.core.security import get_password_hash
from app.models.conversation import Message
from app.models.user import User


def _register(client: TestClient, email: str) -> Any:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPassword123!",
            "firstName": "Test",
            "lastName": email.split("@")[0].title(),
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _me(client: TestClient, headers: dict) -> Any:
    response = client.get("/api/v1/profile/me", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _open(client: TestClient, headers: dict, recipient_id: int) -> Any:
    response = client.post(
        "/api/v1/conversations", json={"recipient_id": recipient_id}, headers=headers
    )
    assert response.status_code == 200, response.text
    return response.json()


def _list(client: TestClient, headers: dict) -> Any:
    response = client.get("/api/v1/conversations", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


class TestConversationsAuth:
    def test_all_routes_require_a_token(self, client: TestClient) -> None:
        assert client.get("/api/v1/conversations").status_code == 401
        assert (
            client.post("/api/v1/conversations", json={"recipient_id": 1}).status_code
            == 401
        )
        assert client.get("/api/v1/conversations/1/messages").status_code == 401
        assert (
            client.post(
                "/api/v1/conversations/1/messages", json={"body": "hello"}
            ).status_code
            == 401
        )


class TestOpenConversation:
    def _pair(self, client: TestClient) -> tuple[dict, int, dict, int]:
        headers_a = _register(client, "alice-thread@example.com")
        headers_b = _register(client, "bob-thread@example.com")
        return (
            headers_a,
            _me(client, headers_a)["id"],
            headers_b,
            _me(client, headers_b)["id"],
        )

    def test_open_is_get_or_create_and_shared_by_both_sides(
        self, client: TestClient
    ) -> None:
        headers_a, id_a, headers_b, id_b = self._pair(client)

        first = _open(client, headers_a, id_b)
        again = _open(client, headers_a, id_b)
        from_b = _open(client, headers_b, id_a)

        assert first["id"] == again["id"] == from_b["id"]
        # The peer field is viewer-relative.
        assert first["peer"]["id"] == id_b
        assert from_b["peer"]["id"] == id_a
        assert first["unread_count"] == 0
        assert first["last_message"] is None

    def test_open_rejects_self_and_unknown_recipients(self, client: TestClient) -> None:
        headers_a, id_a, _, _ = self._pair(client)

        assert (
            client.post(
                "/api/v1/conversations",
                json={"recipient_id": id_a},
                headers=headers_a,
            ).status_code
            == 422
        )
        assert (
            client.post(
                "/api/v1/conversations",
                json={"recipient_id": 999999},
                headers=headers_a,
            ).status_code
            == 404
        )


class TestMessages:
    def _thread(self, client: TestClient) -> tuple[dict, int, dict, int, int]:
        headers_a = _register(client, "alice-msg@example.com")
        headers_b = _register(client, "bob-msg@example.com")
        id_a = _me(client, headers_a)["id"]
        id_b = _me(client, headers_b)["id"]
        conversation = _open(client, headers_a, id_b)
        return headers_a, id_a, headers_b, id_b, conversation["id"]

    def test_send_receive_unread_and_preview(self, client: TestClient) -> None:
        headers_a, id_a, headers_b, _, conversation_id = self._thread(client)

        sent = client.post(
            f"/api/v1/conversations/{conversation_id}/messages",
            json={"body": "  Namaste!  "},
            headers=headers_a,
        )
        assert sent.status_code == 201, sent.text
        assert sent.json()["sender_id"] == id_a
        # Body is trimmed on the way in.
        assert sent.json()["body"] == "Namaste!"

        # Unread accrues for the recipient only — checked *before* the
        # recipient fetches the thread below (fetching marks messages read).
        list_b = _list(client, headers_b)[0]
        assert list_b["unread_count"] == 1
        assert list_b["last_message"]["body"] == "Namaste!"
        assert list_b["peer"]["id"] == id_a

        history = client.get(
            f"/api/v1/conversations/{conversation_id}/messages", headers=headers_b
        )
        assert history.status_code == 200, history.text
        assert [m["body"] for m in history.json()] == ["Namaste!"]

        # The sender never accrues unread for their own message.
        assert _list(client, headers_a)[0]["unread_count"] == 0

    def test_fetching_the_thread_marks_messages_read(self, client: TestClient) -> None:
        headers_a, _, headers_b, _, conversation_id = self._thread(client)
        client.post(
            f"/api/v1/conversations/{conversation_id}/messages",
            json={"body": "Gate opens at 4am"},
            headers=headers_a,
        )
        assert _list(client, headers_b)[0]["unread_count"] == 1

        # Opening the thread clears the count — and polling keeps it clear.
        for _ in range(2):
            assert (
                client.get(
                    f"/api/v1/conversations/{conversation_id}/messages",
                    headers=headers_b,
                ).status_code
                == 200
            )
            assert _list(client, headers_b)[0]["unread_count"] == 0

    def test_blank_messages_are_rejected(self, client: TestClient) -> None:
        headers_a, _, _, _, conversation_id = self._thread(client)
        for body in ("", "   "):
            assert (
                client.post(
                    f"/api/v1/conversations/{conversation_id}/messages",
                    json={"body": body},
                    headers=headers_a,
                ).status_code
                == 422
            )

    def test_non_participants_are_locked_out_with_404(self, client: TestClient) -> None:
        headers_a, _, headers_b, _, conversation_id = self._thread(client)
        outsider = _register(client, "mallory@example.com")

        assert (
            client.get(
                f"/api/v1/conversations/{conversation_id}/messages",
                headers=outsider,
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"/api/v1/conversations/{conversation_id}/messages",
                json={"body": "let me in"},
                headers=outsider,
            ).status_code
            == 404
        )
        # Their own list knows nothing about the thread.
        assert _list(client, outsider) == []


class TestListShape:
    def test_newest_activity_first_and_scoped_per_viewer(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers_a = _register(client, "carol-list@example.com")
        headers_b = _register(client, "dave-list@example.com")
        headers_c = _register(client, "erin-list@example.com")
        id_b = _me(client, headers_b)["id"]
        id_c = _me(client, headers_c)["id"]

        conv_ab = _open(client, headers_a, id_b)
        conv_ac = _open(client, headers_a, id_c)
        client.post(
            f"/api/v1/conversations/{conv_ab['id']}/messages",
            json={"body": "older thread"},
            headers=headers_a,
        )
        client.post(
            f"/api/v1/conversations/{conv_ac['id']}/messages",
            json={"body": "newer thread"},
            headers=headers_a,
        )

        # Give the two messages deterministic, distinct timestamps (the
        # column default has one-second resolution on SQLite).
        rows = db_session.query(Message).order_by(Message.id).all()
        assert len(rows) == 2
        rows[0].created_at = datetime(2026, 1, 1, 10, 0, 0)
        rows[1].created_at = datetime(2026, 1, 2, 10, 0, 0)
        db_session.commit()

        listing = _list(client, headers_a)
        assert [c["id"] for c in listing] == [conv_ac["id"], conv_ab["id"]]
        assert listing[0]["last_message"]["body"] == "newer thread"

        # Dave sees exactly his one thread, with Carol as the peer.
        dave_list = _list(client, headers_b)
        assert [c["id"] for c in dave_list] == [conv_ab["id"]]
        assert dave_list[0]["peer"]["lastName"] == "Carol-List"


class TestBookingGuideExposure:
    def test_bookings_expose_the_assigned_guide_for_messaging(
        self, client: TestClient, db_session: Session
    ) -> None:
        """The Trips tab's "Message guide" entry needs both ids from the
        booking payload; the guide assignment happens at booking time."""
        guide = User(
            email="guide@guides-nepal.com",
            firstName="Test",
            lastName="Guide",
            hashed_password=get_password_hash("Guide@2024"),
            role="guide",
            is_active=True,
        )
        db_session.add(guide)
        db_session.commit()

        traveler = _register(client, "traveler-book@example.com")
        response = client.post(
            "/api/v1/bookings/",
            json={
                "experience_id": 7,
                "experience_title": "Sunrise over Sarangkot",
                "city": "Pokhara",
                "date": "2026-11-02T00:00:00",
                "guests": 2,
                "price": 200.0,
            },
            headers=traveler,
        )
        assert response.status_code == 200, response.text
        booking = response.json()
        assert booking["guide_user_id"] is not None
        assert booking["guide_name"] == "Test Guide"

        # The whole point: the traveler can open that guide's thread.
        conversation = _open(client, traveler, booking["guide_user_id"])
        assert conversation["peer"]["role"] == "guide"
