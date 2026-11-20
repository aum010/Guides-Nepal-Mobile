"""Coverage for the content/CMS router: the in-memory catalogue CRUD, the
media library (uploads, URL imports, placements) and the page-section editor.

Media writes are redirected to ``tmp_path`` so nothing lands in the repo.
"""

import copy
import io
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.orm import Session

import app.api.v1.content as content_module
from app.core.security import create_access_token, get_password_hash
from app.models.user import User

CMS = "/api/v1/content"


def _user(db: Session, role: str = "content-manager", email: str | None = None) -> User:
    user = User(
        email=email or f"{role}@example.com",
        firstName="Content",
        lastName="Editor",
        hashed_password=get_password_hash("TestPassword123!"),
        role=role,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _bearer(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


@pytest.fixture(autouse=True)
def _isolate_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Snapshot the module's in-memory state and redirect media to tmp_path."""
    db_snapshot = copy.deepcopy(content_module.DB)
    next_id = content_module.NEXT_ID
    overrides = copy.deepcopy(content_module.SECTION_OVERRIDES)
    monkeypatch.setattr(content_module, "MEDIA_DIR", str(tmp_path))
    monkeypatch.setattr(
        content_module, "MEDIA_REGISTRY_PATH", str(tmp_path / "registry.json")
    )
    yield
    content_module.DB.clear()
    content_module.DB.update(db_snapshot)
    content_module.NEXT_ID = next_id
    content_module.SECTION_OVERRIDES.clear()
    content_module.SECTION_OVERRIDES.update(overrides)


def _png_bytes() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (8, 8), (10, 20, 30)).save(buffer, format="PNG")
    return buffer.getvalue()


class TestRoleGuards:
    def test_writes_require_cms_roles(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _user(db_session, role="traveler", email="traveler@example.com")

        response = client.post(
            f"{CMS}/blog", json={"title": "Nope"}, headers=_bearer(traveler)
        )

        assert response.status_code == 403

    def test_reads_are_public_where_documented(self, client: TestClient) -> None:
        assert client.get(f"{CMS}/blog").status_code == 200
        assert client.get(f"{CMS}/seo").status_code == 200
        assert client.get(f"{CMS}/placements").status_code == 200
        assert client.get(f"{CMS}/pages/home/sections").status_code == 200


class TestCatalogueCrud:
    def test_pages_crud_round_trip(
        self, client: TestClient, db_session: Session
    ) -> None:
        editor = _user(db_session)
        headers = _bearer(editor)

        listing = client.get(f"{CMS}/pages", headers=headers)
        created = client.post(
            f"{CMS}/pages", json={"slug": "tours", "title": "Tours"}, headers=headers
        )
        updated = client.patch(
            f"{CMS}/pages/{created.json()['id']}",
            json={"title": "All Tours"},
            headers=headers,
        )
        deleted = client.delete(f"{CMS}/pages/{created.json()['id']}", headers=headers)

        assert listing.status_code == 200
        assert listing.json() and "sectionCount" in listing.json()[0]
        assert created.status_code == 200
        assert updated.json()["title"] == "All Tours"
        assert deleted.json()["message"] == "Deleted"

    def test_unknown_items_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        assert (
            client.patch(f"{CMS}/seo/999999", json={}, headers=headers).status_code
            == 404
        )
        assert client.delete(f"{CMS}/guides/999999", headers=headers).status_code == 404

    def test_seo_listing_is_public(self, client: TestClient) -> None:
        response = client.get(f"{CMS}/seo")

        assert response.status_code == 200
        assert response.json()[0]["page"]


class TestBlog:
    def test_anonymous_readers_only_see_published_posts(
        self, client: TestClient
    ) -> None:
        posts = client.get(f"{CMS}/blog").json()

        assert posts
        assert all((p.get("status") or "published") == "published" for p in posts)

    def test_staff_and_admins_see_drafts(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        created = client.post(
            f"{CMS}/blog", json={"title": "Draft post"}, headers=headers
        )

        staff_view = client.get(f"{CMS}/blog", headers=headers).json()
        anon_view = client.get(f"{CMS}/blog").json()

        assert created.json()["status"] == "draft"
        assert created.json()["date"]
        assert any(p["title"] == "Draft post" for p in staff_view)
        assert not any(p["title"] == "Draft post" for p in anon_view)

    def test_anonymous_readers_cannot_fetch_drafts(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        created = client.post(
            f"{CMS}/blog", json={"title": "Hidden"}, headers=headers
        ).json()

        response = client.get(f"{CMS}/blog/{created['id']}")

        assert response.status_code == 404

    def test_staff_can_read_update_and_delete_a_draft(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        post_id = client.post(
            f"{CMS}/blog",
            json={"title": "Editable", "status": "draft"},
            headers=headers,
        ).json()["id"]

        detail = client.get(f"{CMS}/blog/{post_id}", headers=headers)
        updated = client.patch(
            f"{CMS}/blog/{post_id}", json={"title": "Edited"}, headers=headers
        )
        deleted = client.delete(f"{CMS}/blog/{post_id}", headers=headers)

        assert detail.json()["title"] == "Editable"
        assert updated.json()["title"] == "Edited"
        assert deleted.json()["status"] == "ok"


class TestMediaLibrary:
    def test_upload_lists_and_deletes_an_image(
        self, client: TestClient, db_session: Session, tmp_path: Path
    ) -> None:
        headers = _bearer(_user(db_session))

        uploaded = client.post(
            f"{CMS}/media/upload",
            files={"file": ("hero.png", _png_bytes(), "image/png")},
            headers=headers,
        )
        listing = client.get(f"{CMS}/media", headers=headers)
        deleted = client.delete(f"{CMS}/media/{uploaded.json()['id']}", headers=headers)

        assert uploaded.status_code == 200, uploaded.text
        assert uploaded.json()["original_name"] == "hero.png"
        assert uploaded.json()["url"].startswith("http")
        assert any(item["id"] == uploaded.json()["id"] for item in listing.json())
        assert deleted.json()["message"] == "Deleted"

    def test_upload_rejects_an_empty_file(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        response = client.post(
            f"{CMS}/media/upload",
            files={"file": ("empty.png", b"", "image/png")},
            headers=headers,
        )

        assert response.status_code == 422

    def test_upload_can_replace_an_existing_item(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        first = client.post(
            f"{CMS}/media/upload",
            files={"file": ("a.png", _png_bytes(), "image/png")},
            headers=headers,
        ).json()

        replaced = client.post(
            f"{CMS}/media/upload",
            params={"replace_id": first["id"]},
            files={"file": ("b.png", _png_bytes(), "image/png")},
            headers=headers,
        )

        assert replaced.status_code == 200, replaced.text
        assert replaced.json()["id"] == first["id"]
        # The library entry keeps its identity; only the file behind it swaps.
        assert replaced.json()["original_name"] == "a.png"
        assert "b.png" in replaced.json()["filename"]
        assert len(client.get(f"{CMS}/media", headers=headers).json()) == 1

    def test_replace_of_an_unknown_item_is_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        response = client.post(
            f"{CMS}/media/upload",
            params={"replace_id": 999999},
            files={"file": ("a.png", _png_bytes(), "image/png")},
            headers=headers,
        )

        assert response.status_code == 404

    def test_upload_from_url_stores_the_download(
        self, client: TestClient, db_session: Session, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        headers = _bearer(_user(db_session))

        class _Download:
            content = _png_bytes()
            headers = {"Content-Type": "image/png"}

            def raise_for_status(self) -> None:
                return None

        monkeypatch.setattr(httpx, "get", lambda *a, **k: _Download())

        response = client.post(
            f"{CMS}/media/upload-url",
            json={"url": "https://images.example.com/pretty%20view.png"},
            headers=headers,
        )

        assert response.status_code == 200, response.text
        assert response.json()["original_name"] == "pretty_20view.png"
        assert response.json()["source_url"].endswith("pretty%20view.png")

    @pytest.mark.parametrize(
        ("payload", "status_code"),
        [
            ({}, 422),
            ({"url": "ftp://example.com/a.png"}, 422),
            ({"url": "https://example.com/a.png"}, 400),
        ],
    )
    def test_upload_from_url_validates_input(
        self,
        client: TestClient,
        db_session: Session,
        monkeypatch: pytest.MonkeyPatch,
        payload: dict[str, Any],
        status_code: int,
    ) -> None:
        headers = _bearer(_user(db_session))

        def exploding_get(*args: Any, **kwargs: Any) -> Any:
            raise httpx.ConnectError("offline")

        monkeypatch.setattr(httpx, "get", exploding_get)

        response = client.post(f"{CMS}/media/upload-url", json=payload, headers=headers)

        assert response.status_code == status_code

    def test_media_can_be_renamed_and_unknown_ids_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        item = client.post(
            f"{CMS}/media/upload",
            files={"file": ("a.png", _png_bytes(), "image/png")},
            headers=headers,
        ).json()

        renamed = client.patch(
            f"{CMS}/media/{item['id']}",
            json={"original_name": "renamed.png", "id": 12345},
            headers=headers,
        )
        missing = client.patch(f"{CMS}/media/999999", json={}, headers=headers)
        missing_delete = client.delete(f"{CMS}/media/999999", headers=headers)

        assert renamed.json()["original_name"] == "renamed.png"
        assert renamed.json()["id"] == item["id"]
        assert missing.status_code == 404
        assert missing_delete.status_code == 404


class TestPlacements:
    def test_placements_can_be_set_listed_and_cleared(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        item = client.post(
            f"{CMS}/media/upload",
            files={"file": ("a.png", _png_bytes(), "image/png")},
            headers=headers,
        ).json()

        placed = client.put(
            f"{CMS}/placements/home-promo",
            json={"media_id": item["id"]},
            headers=headers,
        )
        listed = client.get(f"{CMS}/placements")
        cleared = client.delete(f"{CMS}/placements/home-promo", headers=headers)
        after = client.get(f"{CMS}/placements")

        assert placed.status_code == 200
        assert listed.json()["placements"]["home-promo"].endswith(item["filename"])
        assert any(slot["key"] == "home-promo" for slot in listed.json()["slots"])
        assert cleared.json()["status"] == "ok"
        assert "home-promo" not in after.json()["placements"]

    def test_unknown_slots_and_media_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        bad_slot = client.put(
            f"{CMS}/placements/nope", json={"media_id": 1}, headers=headers
        )
        bad_media = client.put(
            f"{CMS}/placements/home-promo", json={"media_id": 999999}, headers=headers
        )

        assert bad_slot.status_code == 404
        assert bad_media.status_code == 404


class TestPageSections:
    def test_default_sections_are_served(self, client: TestClient) -> None:
        response = client.get(f"{CMS}/pages/about/sections")

        assert response.status_code == 200
        types = [s["type"] for s in response.json()["sections"]]
        assert types[:2] == ["hero", "text"]

    def test_unknown_pages_return_an_empty_template(self, client: TestClient) -> None:
        response = client.get(f"{CMS}/pages/unknown-page/sections")

        assert response.json()["sections"] == []

    def test_sections_can_be_created_updated_and_deleted(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        created = client.post(
            f"{CMS}/pages/about/sections",
            json={"title": "Extra", "type": "text", "content": {"body": "hi"}},
            headers=headers,
        )
        section_id = created.json()["section"]["id"]
        updated = client.put(
            f"{CMS}/pages/about/sections/{section_id}",
            json={"content": {"body": "edited"}},
            headers=headers,
        )
        deleted = client.delete(
            f"{CMS}/pages/about/sections/{section_id}", headers=headers
        )
        missing = client.delete(
            f"{CMS}/pages/about/sections/{section_id}", headers=headers
        )

        assert created.json()["status"] == "ok"
        assert updated.json()["section"]["content"]["body"] == "edited"
        assert deleted.json()["message"] == "Section deleted"
        assert missing.status_code == 404

    def test_upsert_updates_an_existing_default_section(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))

        response = client.post(
            f"{CMS}/pages/about/sections",
            json={"id": "about-hero", "title": "New hero"},
            headers=headers,
        )

        assert response.json()["section"]["id"] == "about-hero"
        assert response.json()["section"]["title"] == "New hero"

    def test_all_sections_can_be_replaced(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        sections = [{"id": "only", "title": "Only", "type": "text"}]

        response = client.put(
            f"{CMS}/pages/about/sections", json={"sections": sections}, headers=headers
        )
        reread = client.get(f"{CMS}/pages/about/sections")

        assert response.json()["count"] == 1
        assert reread.json()["sections"][0]["id"] == "only"

    def test_section_edits_are_persisted_per_page(
        self, client: TestClient, db_session: Session
    ) -> None:
        headers = _bearer(_user(db_session))
        client.put(
            f"{CMS}/pages/contact/sections",
            json={"sections": [{"id": "c1", "title": "Contact"}]},
            headers=headers,
        )

        contact = client.get(f"{CMS}/pages/contact/sections").json()
        about = client.get(f"{CMS}/pages/about/sections").json()

        assert contact["sections"][0]["id"] == "c1"
        assert about["sections"][0]["id"] == "about-hero"
