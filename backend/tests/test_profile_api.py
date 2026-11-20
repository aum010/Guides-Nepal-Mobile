"""Profile endpoints: read/update of the signed-in user, avatar upload,
and the bookmark list/add/remove round trip."""

import os

from fastapi.testclient import TestClient

PROFILE = "/api/v1/profile"

PNG_BYTES = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000d49444154789c6360000002000100ffff03000006000557bfabd400"
    "00000049454e44ae426082"
)


def _register(client: TestClient, email: str) -> tuple[dict, int]:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPassword123!",
            "firstName": "Pema",
            "lastName": email.split("@")[0].title(),
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    headers = {"Authorization": f"Bearer {body['access_token']}"}
    user_id = client.get(f"{PROFILE}/me", headers=headers).json()["id"]
    return headers, user_id


class TestProfileReadUpdate:
    def test_me_requires_a_token(self, client: TestClient) -> None:
        assert client.get(f"{PROFILE}/me").status_code == 401
        assert client.patch(f"{PROFILE}/me", json={}).status_code == 401

    def test_me_returns_the_signed_in_user(self, client: TestClient) -> None:
        headers, user_id = _register(client, "readme@example.com")
        response = client.get(f"{PROFILE}/me", headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["id"] == user_id
        assert body["email"] == "readme@example.com"
        assert body["firstName"] == "Pema"

    def test_patch_updates_and_persists_profile_fields(
        self, client: TestClient
    ) -> None:
        headers, _ = _register(client, "patchme@example.com")
        patched = client.patch(
            f"{PROFILE}/me",
            json={
                "phone": "9800000001",
                "bio": "Weekend rambler.",
                "avatar_url": "/uploads/1/me.png",
            },
            headers=headers,
        )
        assert patched.status_code == 200, patched.text
        assert patched.json() == {"status": "ok"}

        reread = client.get(f"{PROFILE}/me", headers=headers).json()
        assert reread["phone"] == "9800000001"
        assert reread["bio"] == "Weekend rambler."
        assert reread["avatarUrl"] == "/uploads/1/me.png"


class TestAvatarUpload:
    def test_upload_stores_the_file_and_returns_its_url(
        self, client: TestClient
    ) -> None:
        headers, user_id = _register(client, "avatar@example.com")
        response = client.post(
            f"{PROFILE}/photos/upload",
            files={"file": ("my avatar!.png", PNG_BYTES, "image/png")},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        url = response.json()["url"]
        assert url.startswith(f"/uploads/{user_id}/")

        uploads_root = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../uploads")
        )
        user_dir = os.path.join(uploads_root, str(user_id))
        saved_name = url.rsplit("/", 1)[-1]
        saved_path = os.path.join(user_dir, saved_name)
        try:
            assert os.path.exists(saved_path)
            with open(saved_path, "rb") as handle:
                assert handle.read() == PNG_BYTES
        finally:
            if os.path.exists(saved_path):
                os.remove(saved_path)
            if os.path.isdir(user_dir) and not os.listdir(user_dir):
                os.rmdir(user_dir)

    def test_upload_requires_a_token(self, client: TestClient) -> None:
        response = client.post(
            f"{PROFILE}/photos/upload",
            files={"file": ("x.png", PNG_BYTES, "image/png")},
        )
        assert response.status_code == 401


class TestBookmarks:
    def test_add_list_and_delete_round_trip(self, client: TestClient) -> None:
        headers, _ = _register(client, "bookmarker@example.com")

        added = client.post(
            f"{PROFILE}/bookmarks",
            json={
                "title": "Sarangkot Sunrise",
                "city": "Pokhara",
                "image": "/img.jpg",
                "experience_id": 42,
            },
            headers=headers,
        )
        assert added.status_code == 200, added.text
        bookmark_id = added.json()["id"]
        assert added.json()["title"] == "Sarangkot Sunrise"
        # The experience back-reference round-trips, so clients stop matching
        # on the free-form link alone.
        assert added.json()["experience_id"] == 42

        listed = client.get(f"{PROFILE}/bookmarks", headers=headers)
        assert listed.status_code == 200
        assert [row["id"] for row in listed.json()] == [bookmark_id]
        assert listed.json()[0]["experience_id"] == 42

        deleted = client.delete(f"{PROFILE}/bookmarks/{bookmark_id}", headers=headers)
        assert deleted.status_code == 200
        assert deleted.json() == {"status": "ok"}
        assert client.get(f"{PROFILE}/bookmarks", headers=headers).json() == []

        again = client.delete(f"{PROFILE}/bookmarks/{bookmark_id}", headers=headers)
        assert again.status_code == 404

    def test_bookmarks_are_scoped_to_their_owner(self, client: TestClient) -> None:
        owner_headers, _ = _register(client, "bm-owner@example.com")
        stranger_headers, _ = _register(client, "bm-stranger@example.com")
        added = client.post(
            f"{PROFILE}/bookmarks",
            json={"title": "Private bookmark"},
            headers=owner_headers,
        )
        bookmark_id = added.json()["id"]

        # The stranger cannot see or remove it; their list stays empty.
        assert client.get(f"{PROFILE}/bookmarks", headers=stranger_headers).json() == []
        assert (
            client.delete(
                f"{PROFILE}/bookmarks/{bookmark_id}", headers=stranger_headers
            ).status_code
            == 404
        )

    def test_bookmark_routes_require_auth(self, client: TestClient) -> None:
        assert client.get(f"{PROFILE}/bookmarks").status_code == 401
        assert (
            client.post(f"{PROFILE}/bookmarks", json={"title": "x"}).status_code == 401
        )
        assert client.delete(f"{PROFILE}/bookmarks/1").status_code == 401
