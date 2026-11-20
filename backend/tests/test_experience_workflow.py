"""Tests for the experience workflow (SOP-GN-EXP-001 / SOP-GN-EXP-002).

These cover the two approval gates end-to-end:

- Proposals: Regional Manager **or** Content Writer may authorize.
- Change requests: Regional Manager **only** — Content Writer is 403.

Plus the SOP-aligned state machine (draft → submitted → approved →
published/applied) and ownership scoping.
"""

from typing import Any
from sqlalchemy.orm import Session
from fastapi.testclient import TestClient

import pytest

from app.core.roles import ADMIN, CONTENT_MANAGER, GUIDE, REGIONAL_HEAD, TRAVELER
from app.core.security import create_access_token, get_password_hash
from app.models.guide_listing import GuideListing
from app.models.user import User

BASE = "/api/v1/experience-workflow"
PROPOSALS = f"{BASE}/proposals"
CHANGE_REQUESTS = f"{BASE}/change-requests"
PROPOSAL_QUEUE = f"{BASE}/queue/proposals"
CHANGE_REQUEST_QUEUE = f"{BASE}/queue/change-requests"

STRONG_PASSWORD = "Guide@2024"

VALID_PROPOSAL: dict[str, Any] = {
    "title": "Sunrise Kayak on Phewa Lake",
    "category": "tour",
    "city": "Pokhara",
    "area": "Phewa Lake",
    "description": "Paddle out before dawn to watch the sun rise over the Annapurnas.",
    "itinerary": "05:00 meet at the boathouse, 05:30 on the water, 07:30 breakfast on shore.",
    "meeting_point": "Phewa Lake boathouse",
    "duration": "3 hours",
    "difficulty": "Easy",
    "price": 45.0,
    "max_guests": 8,
    "documents": [
        {"name": "Risk assessment", "url": "https://docs.example.com/risk.pdf"}
    ],
}


def _make_user(db_session: Session, email: str, role: str) -> User:
    user = User(
        email=email,
        hashed_password=get_password_hash(STRONG_PASSWORD),
        firstName=email.split("@")[0].title(),
        lastName="Tester",
        role=role,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def _make_listing(db_session: Session, guide: User, **overrides: Any) -> GuideListing:
    defaults = {
        "guide_user_id": guide.id,
        "title": "Bhaktapur Heritage Walk",
        "category": "tour",
        "city": "Bhaktapur",
        "description": "A slow walk through the pottery square and old palace lanes.",
        "duration": "4 hours",
        "difficulty": "Easy",
        "price": 50.0,
        "max_guests": 10,
        "is_active": True,
    }
    defaults.update(overrides)
    listing = GuideListing(**defaults)
    db_session.add(listing)
    db_session.commit()
    db_session.refresh(listing)
    return listing


def _bearer(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _create_and_submit_proposal(client: TestClient, guide: User) -> Any:
    res = client.post(PROPOSALS, json=VALID_PROPOSAL, headers=_bearer(guide))
    assert res.status_code == 201
    proposal_id = res.json()["id"]
    res = client.post(f"{PROPOSALS}/{proposal_id}/submit", headers=_bearer(guide))
    assert res.status_code == 200
    assert res.json()["status"] == "submitted"
    return res.json()


def _create_and_submit_cr(
    client: TestClient, guide: User, listing_id: int, **extra: Any
) -> Any:
    payload = {
        "listing_id": listing_id,
        "reason": "Seasonal price update after fuel costs rose.",
        "changes": [{"field": "price", "proposed": 65.0}],
    }
    payload.update(extra)
    res = client.post(CHANGE_REQUESTS, json=payload, headers=_bearer(guide))
    assert res.status_code == 201, res.text
    cr = res.json()
    res = client.post(f"{CHANGE_REQUESTS}/{cr['id']}/submit", headers=_bearer(guide))
    assert res.status_code == 200
    assert res.json()["status"] == "submitted"
    return res.json()


class TestProposalLifecycle:
    def test_full_lifecycle_to_published_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "kayak-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)

        # Regional Manager approves (SOP-GN-EXP-001 approval gate).
        rm = _make_user(db_session, "rm@example.com", REGIONAL_HEAD)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve", "notes": "Solid safety plan."},
            headers=_bearer(rm),
        )
        assert res.status_code == 200
        body = res.json()
        assert body["status"] == "approved"
        assert body["decided_by_role"] == REGIONAL_HEAD

        # Guide publishes within the SLA — listing goes live.
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/publish", headers=_bearer(guide)
        )
        assert res.status_code == 200
        assert res.json()["status"] == "published"
        listing_id = res.json()["listing_id"]
        assert listing_id is not None

        listing = db_session.get(GuideListing, listing_id)
        assert listing is not None
        assert listing.guide_user_id == guide.id
        assert listing.title == VALID_PROPOSAL["title"]
        assert listing.is_active is True

    def test_content_writer_may_approve_a_proposal(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cw-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        cw = _make_user(db_session, "cw@example.com", CONTENT_MANAGER)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(cw),
        )
        assert res.status_code == 200
        assert res.json()["decided_by_role"] == CONTENT_MANAGER

    def test_admin_is_implicitly_authorized(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "admin-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        admin = _make_user(db_session, "boss@example.com", ADMIN)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(admin),
        )
        assert res.status_code == 200

    @pytest.mark.parametrize("role", [GUIDE, TRAVELER, "customer-support", "host"])
    def test_unauthorized_roles_cannot_decide_proposals(
        self, client: TestClient, db_session: Session, role: str
    ) -> None:
        guide = _make_user(db_session, "gate-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        outsider = _make_user(db_session, f"outsider-{role}@example.com", role)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(outsider),
        )
        assert res.status_code == 403

    def test_reject_requires_notes(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "notes-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        rm = _make_user(db_session, "notes-rm@example.com", REGIONAL_HEAD)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "reject"},
            headers=_bearer(rm),
        )
        assert res.status_code == 422

    def test_submitted_proposal_cannot_be_edited(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "edit-guide@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        res = client.patch(
            f"{PROPOSALS}/{proposal['id']}",
            json={"price": 99.0},
            headers=_bearer(guide),
        )
        assert res.status_code == 422

    def test_unapproved_proposal_cannot_be_published(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "premature@example.com", GUIDE)
        res = client.post(PROPOSALS, json=VALID_PROPOSAL, headers=_bearer(guide))
        proposal_id = res.json()["id"]
        res = client.post(f"{PROPOSALS}/{proposal_id}/publish", headers=_bearer(guide))
        assert res.status_code == 422

    def test_guide_only_sees_their_own_proposals(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide_a = _make_user(db_session, "guide-a@example.com", GUIDE)
        guide_b = _make_user(db_session, "guide-b@example.com", GUIDE)
        res = client.post(PROPOSALS, json=VALID_PROPOSAL, headers=_bearer(guide_a))
        proposal_id = res.json()["id"]
        # Guide B cannot read, edit or submit Guide A's proposal.
        assert (
            client.get(
                f"{PROPOSALS}/{proposal_id}", headers=_bearer(guide_b)
            ).status_code
            == 404
        )
        assert (
            client.post(
                f"{PROPOSALS}/{proposal_id}/submit", headers=_bearer(guide_b)
            ).status_code
            == 404
        )
        assert client.get(PROPOSALS, headers=_bearer(guide_b)).json() == []

    def test_non_guide_cannot_create_proposals(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _make_user(db_session, "wanderer@example.com", TRAVELER)
        res = client.post(PROPOSALS, json=VALID_PROPOSAL, headers=_bearer(traveler))
        assert res.status_code == 403

    def test_resubmission_clears_previous_decision(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "resub@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        rm = _make_user(db_session, "resub-rm@example.com", REGIONAL_HEAD)
        client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "request_changes", "notes": "Add meal inclusions."},
            headers=_bearer(rm),
        )
        # Guide edits (allowed in changes_requested) and resubmits — clock resets.
        res = client.patch(
            f"{PROPOSALS}/{proposal['id']}",
            json={"description": VALID_PROPOSAL["description"] + " Meals included."},
            headers=_bearer(guide),
        )
        assert res.status_code == 200
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/submit", headers=_bearer(guide)
        )
        body = res.json()
        assert body["status"] == "submitted"
        assert body["decided_at"] is None
        assert body["decision_notes"] is None

    def test_withdraw(self, client: TestClient, db_session: Session) -> None:
        guide = _make_user(db_session, "withdraw@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/withdraw", headers=_bearer(guide)
        )
        assert res.status_code == 200
        assert res.json()["status"] == "cancelled"

    def test_rejection_closes_the_request(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "closed@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        rm = _make_user(db_session, "closed-rm@example.com", REGIONAL_HEAD)
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "reject", "notes": "Duplicates a seasonal listing."},
            headers=_bearer(rm),
        )
        assert res.status_code == 200
        body = res.json()
        assert body["status"] == "rejected"
        assert "Duplicates" in body["decision_notes"]
        # A rejected proposal can never be published.
        res = client.post(
            f"{PROPOSALS}/{proposal['id']}/publish", headers=_bearer(guide)
        )
        assert res.status_code == 422


class TestChangeRequestLifecycle:
    def test_full_lifecycle_apply_updates_listing(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-guide@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)

        # Server-side snapshot: current → proposed (SOP-GN-EXP-002 form EXP-F-002).
        assert cr["change_class"] == "material"
        assert cr["changes"] == [{"field": "price", "current": 50.0, "proposed": 65.0}]

        rm = _make_user(db_session, "cr-rm@example.com", REGIONAL_HEAD)
        res = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "approve", "notes": "Market rate OK."},
            headers=_bearer(rm),
        )
        assert res.status_code == 200
        assert res.json()["decided_by_role"] == REGIONAL_HEAD

        # Guide applies the approved change (Step 6a) — only the reviewed diff.
        res = client.post(f"{CHANGE_REQUESTS}/{cr['id']}/apply", headers=_bearer(guide))
        assert res.status_code == 200
        assert res.json()["status"] == "applied"
        db_session.refresh(listing)
        assert listing.price == 65.0
        assert listing.title == "Bhaktapur Heritage Walk"  # untouched fields stay

    def test_content_writer_cannot_decide_change_requests(
        self, client: TestClient, db_session: Session
    ) -> None:
        """SOP-GN-EXP-002 gate: Regional Manager ONLY."""
        guide = _make_user(db_session, "cw-cr-guide@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        cw = _make_user(db_session, "cw-cr@example.com", CONTENT_MANAGER)
        res = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(cw),
        )
        assert res.status_code == 403

    @pytest.mark.parametrize("role", [GUIDE, TRAVELER, "customer-support", "host"])
    def test_unauthorized_roles_cannot_decide_change_requests(
        self, client: TestClient, db_session: Session, role: str
    ) -> None:
        guide = _make_user(db_session, f"cr-gate-{role}@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        outsider = _make_user(db_session, f"cr-outsider-{role}@example.com", role)
        res = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(outsider),
        )
        assert res.status_code == 403

    def test_minor_change_is_classified_editorial(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "minor-guide@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        res = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Polished the description wording.",
                "changes": [
                    {
                        "field": "description",
                        "proposed": "A gentle walk through Bhaktapur's pottery square, palace lanes and hidden courtyards.",
                    }
                ],
            },
            headers=_bearer(guide),
        )
        assert res.status_code == 201
        assert res.json()["change_class"] == "minor"

    def test_noop_change_is_rejected(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "noop@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        res = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Trying to set the same price.",
                "changes": [{"field": "price", "proposed": listing.price}],
            },
            headers=_bearer(guide),
        )
        assert res.status_code == 422

    def test_max_guests_below_booked_is_rejected(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "capacity@example.com", GUIDE)
        listing = _make_listing(db_session, guide, max_guests=10, booked_guests=8)
        res = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Reducing group size for the season.",
                "changes": [{"field": "max_guests", "proposed": 6}],
            },
            headers=_bearer(guide),
        )
        assert res.status_code == 422
        assert "booked" in res.json()["detail"]

    def test_unknown_field_is_rejected(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "unknown-field@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        res = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Attempting an unsupported field edit.",
                "changes": [{"field": "guide_user_id", "proposed": 999}],
            },
            headers=_bearer(guide),
        )
        assert res.status_code == 422

    def test_cannot_apply_an_unapproved_change_request(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "apply-early@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        res = client.post(f"{CHANGE_REQUESTS}/{cr['id']}/apply", headers=_bearer(guide))
        assert res.status_code == 422
        db_session.refresh(listing)
        assert listing.price == 50.0  # unchanged

    def test_change_request_only_touches_owned_listings(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide_a = _make_user(db_session, "owner@example.com", GUIDE)
        guide_b = _make_user(db_session, "intruder@example.com", GUIDE)
        listing = _make_listing(db_session, guide_a)
        res = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Someone else's listing edit attempt.",
                "changes": [{"field": "price", "proposed": 1.0}],
            },
            headers=_bearer(guide_b),
        )
        assert res.status_code == 404


class TestApproverQueues:
    def test_proposal_queue_visible_to_both_approver_roles(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "queue-guide@example.com", GUIDE)
        _create_and_submit_proposal(client, guide)
        for role, email in (
            (REGIONAL_HEAD, "queue-rm@example.com"),
            (CONTENT_MANAGER, "queue-cw@example.com"),
        ):
            user = _make_user(db_session, email, role)
            res = client.get(PROPOSAL_QUEUE, headers=_bearer(user))
            assert res.status_code == 200
            assert len(res.json()) == 1
            assert res.json()[0]["guide_email"] == guide.email

    def test_change_request_queue_is_regional_manager_only(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "crq-guide@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        rm = _make_user(db_session, "crq-rm@example.com", REGIONAL_HEAD)
        res = client.get(CHANGE_REQUEST_QUEUE, headers=_bearer(rm))
        assert res.status_code == 200
        assert res.json()[0]["id"] == cr["id"]
        cw = _make_user(db_session, "crq-cw@example.com", CONTENT_MANAGER)
        assert client.get(CHANGE_REQUEST_QUEUE, headers=_bearer(cw)).status_code == 403

    def test_guide_cannot_read_any_queue(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "nosy@example.com", GUIDE)
        assert client.get(PROPOSAL_QUEUE, headers=_bearer(guide)).status_code == 403
        assert (
            client.get(CHANGE_REQUEST_QUEUE, headers=_bearer(guide)).status_code == 403
        )

    def test_queues_can_be_filtered_by_status(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "queue-filter@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        _create_and_submit_proposal(client, guide)
        _create_and_submit_cr(client, guide, listing.id)
        rm = _make_user(db_session, "queue-filter-rm@example.com", REGIONAL_HEAD)

        submitted = client.get(PROPOSAL_QUEUE, headers=_bearer(rm)).json()
        drafts = client.get(
            PROPOSAL_QUEUE, params={"status": "draft"}, headers=_bearer(rm)
        ).json()
        everything = client.get(
            CHANGE_REQUEST_QUEUE, params={"status": "all"}, headers=_bearer(rm)
        ).json()

        assert len(submitted) == 1
        assert drafts == []
        assert len(everything) == 1


class TestChangeRequestValidation:
    """Every proposed value is validated server-side before it is recorded."""

    def _propose(
        self,
        client: TestClient,
        guide: User,
        listing: GuideListing,
        field: str,
        value: Any,
    ) -> Any:
        return client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Validation probe for the change request form.",
                "changes": [{"field": field, "proposed": value}],
            },
            headers=_bearer(guide),
        )

    @pytest.mark.parametrize(
        ("field", "value", "detail"),
        [
            ("title", "ab", "between 3 and 160"),
            ("title", "   ", "non-empty string"),
            ("title", 42, "non-empty string"),
            ("description", "too short", "between 10 and 5000"),
            ("category", "skiing", "category must be one of"),
            ("price", "free", "price must be a number"),
            ("price", -5, "price cannot be negative"),
            ("max_guests", "many", "max_guests must be a whole number"),
            ("max_guests", 0, "between 1 and 100"),
            ("max_guests", 101, "between 1 and 100"),
            ("is_active", "yes", "is_active must be true or false"),
            ("duration", 7, "non-empty string"),
        ],
    )
    def test_invalid_values_are_rejected(
        self,
        client: TestClient,
        db_session: Session,
        field: str,
        value: Any,
        detail: str,
    ) -> None:
        guide = _make_user(db_session, f"invalid-{field}@example.com", GUIDE)
        listing = _make_listing(db_session, guide)

        response = self._propose(client, guide, listing, field, value)

        assert response.status_code == 422
        assert detail in response.json()["detail"]

    def test_duplicate_fields_are_rejected(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "dupe-field@example.com", GUIDE)
        listing = _make_listing(db_session, guide)

        response = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Two edits to the same field.",
                "changes": [
                    {"field": "price", "proposed": 60.0},
                    {"field": "price", "proposed": 70.0},
                ],
            },
            headers=_bearer(guide),
        )

        assert response.status_code == 422
        assert "listed more than once" in response.json()["detail"]

    def test_an_empty_change_set_is_rejected_by_the_schema(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "empty-changes@example.com", GUIDE)
        listing = _make_listing(db_session, guide)

        response = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Nothing to change at all.",
                "changes": [],
            },
            headers=_bearer(guide),
        )

        assert response.status_code == 422

    def test_boolean_toggles_are_accepted(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "toggle@example.com", GUIDE)
        listing = _make_listing(db_session, guide)

        response = self._propose(client, guide, listing, "is_active", False)

        assert response.status_code == 201, response.text
        assert response.json()["change_class"] == "material"


class TestChangeRequestEdges:
    def test_drafts_can_be_edited_and_reclassified(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-edit@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        created = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Start with an editorial tweak.",
                "changes": [
                    {
                        "field": "description",
                        "proposed": "A very different description for the walk.",
                    }
                ],
            },
            headers=_bearer(guide),
        ).json()

        response = client.patch(
            f"{CHANGE_REQUESTS}/{created['id']}",
            json={
                "changes": [{"field": "price", "proposed": 71.0}],
                "reason": "Fuel costs moved, so the price has to move too.",
            },
            headers=_bearer(guide),
        )

        assert response.status_code == 200, response.text
        assert response.json()["change_class"] == "material"
        assert response.json()["changes"][0]["field"] == "price"
        assert "Fuel costs" in response.json()["reason"]

    def test_submitted_requests_are_frozen(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-frozen@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)

        edited = client.patch(
            f"{CHANGE_REQUESTS}/{cr['id']}",
            json={"reason": "Too late to change this reason."},
            headers=_bearer(guide),
        )
        resubmitted = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/submit", headers=_bearer(guide)
        )

        assert edited.status_code == 422
        assert "cannot be edited" in edited.json()["detail"]
        assert resubmitted.status_code == 422

    def test_only_submitted_requests_can_be_withdrawn(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-withdraw@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        created = client.post(
            CHANGE_REQUESTS,
            json={
                "listing_id": listing.id,
                "reason": "Withdrawing before submitting.",
                "changes": [{"field": "price", "proposed": 55.0}],
            },
            headers=_bearer(guide),
        ).json()

        response = client.post(
            f"{CHANGE_REQUESTS}/{created['id']}/withdraw", headers=_bearer(guide)
        )

        assert response.status_code == 422
        assert "Only a submitted" in response.json()["detail"]

    def test_decisions_require_notes_for_changes_and_rejection(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-notes@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        rm = _make_user(db_session, "cr-notes-rm@example.com", REGIONAL_HEAD)

        response = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "request_changes"},
            headers=_bearer(rm),
        )

        assert response.status_code == 422
        assert "Notes are required" in response.json()["detail"]

    def test_changes_requested_can_be_edited_and_resubmitted(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-rework@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(client, guide, listing.id)
        rm = _make_user(db_session, "cr-rework-rm@example.com", REGIONAL_HEAD)
        client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "request_changes", "notes": "Justify the price."},
            headers=_bearer(rm),
        )

        edited = client.patch(
            f"{CHANGE_REQUESTS}/{cr['id']}",
            json={"reason": "Fuel costs rose 20% this season."},
            headers=_bearer(guide),
        )
        resubmitted = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/submit", headers=_bearer(guide)
        )

        assert edited.status_code == 200
        assert resubmitted.status_code == 200
        assert resubmitted.json()["status"] == "submitted"
        assert resubmitted.json()["decided_at"] is None

    def test_apply_rechecks_the_capacity_guard(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-capacity@example.com", GUIDE)
        listing = _make_listing(db_session, guide)
        cr = _create_and_submit_cr(
            client,
            guide,
            listing.id,
            changes=[{"field": "max_guests", "proposed": 6}],
        )
        rm = _make_user(db_session, "cr-capacity-rm@example.com", REGIONAL_HEAD)
        client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(rm),
        )
        # Bookings grew while the request was waiting for approval.
        listing.booked_guests = 9
        db_session.commit()

        response = client.post(
            f"{CHANGE_REQUESTS}/{cr['id']}/apply", headers=_bearer(guide)
        )

        assert response.status_code == 422
        assert "below booked guests" in response.json()["detail"]
        db_session.refresh(listing)
        assert listing.max_guests == 10

    def test_unknown_change_requests_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "cr-missing@example.com", GUIDE)
        rm = _make_user(db_session, "cr-missing-rm@example.com", REGIONAL_HEAD)

        assert (
            client.get(f"{CHANGE_REQUESTS}/999999", headers=_bearer(guide)).status_code
            == 404
        )
        assert (
            client.post(
                f"{CHANGE_REQUESTS}/999999/decision",
                json={"action": "approve"},
                headers=_bearer(rm),
            ).status_code
            == 404
        )


class TestProposalEdges:
    def test_a_proposal_cannot_be_published_twice(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "publish-twice@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        rm = _make_user(db_session, "publish-twice-rm@example.com", REGIONAL_HEAD)
        client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(rm),
        )
        first = client.post(
            f"{PROPOSALS}/{proposal['id']}/publish", headers=_bearer(guide)
        )

        second = client.post(
            f"{PROPOSALS}/{proposal['id']}/publish", headers=_bearer(guide)
        )

        assert first.status_code == 200, first.text
        assert first.json()["status"] == "published"
        assert first.json()["listing_id"] is not None
        assert second.status_code == 422

    def test_only_submitted_proposals_can_be_withdrawn(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "proposal-withdraw@example.com", GUIDE)
        proposal = client.post(
            PROPOSALS, json=VALID_PROPOSAL, headers=_bearer(guide)
        ).json()

        response = client.post(
            f"{PROPOSALS}/{proposal['id']}/withdraw", headers=_bearer(guide)
        )

        assert response.status_code == 422

    def test_unknown_proposals_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "proposal-missing@example.com", GUIDE)
        rm = _make_user(db_session, "proposal-missing-rm@example.com", REGIONAL_HEAD)

        assert (
            client.get(f"{PROPOSALS}/999999", headers=_bearer(guide)).status_code == 404
        )
        assert (
            client.post(
                f"{PROPOSALS}/999999/decision",
                json={"action": "approve"},
                headers=_bearer(rm),
            ).status_code
            == 404
        )

    def test_a_published_proposal_cannot_be_decided_again(
        self, client: TestClient, db_session: Session
    ) -> None:
        guide = _make_user(db_session, "decide-twice@example.com", GUIDE)
        proposal = _create_and_submit_proposal(client, guide)
        rm = _make_user(db_session, "decide-twice-rm@example.com", REGIONAL_HEAD)
        client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "approve"},
            headers=_bearer(rm),
        )

        response = client.post(
            f"{PROPOSALS}/{proposal['id']}/decision",
            json={"action": "reject", "notes": "Changed my mind."},
            headers=_bearer(rm),
        )

        assert response.status_code == 422
        assert "Only a submitted proposal" in response.json()["detail"]
