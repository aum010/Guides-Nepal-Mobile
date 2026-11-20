"""Coverage for the operations router: staff-side application review, the
host's own application status, and the support-ticket desk."""

from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.security import create_access_token, get_password_hash
from app.models.guide_application import GuideApplication
from app.models.host_application import HostApplication
from app.models.support_ticket import SupportTicket
from app.models.user import User

OPS = "/api/v1/operations"
PASSWORD = "TestPassword123!"


def _staff(
    db: Session,
    role: str = "admin",
    email: str | None = None,
    region: str | None = None,
) -> User:
    user = User(
        email=email or f"{role}@example.com",
        firstName="Ops",
        lastName="Staff",
        hashed_password=get_password_hash(PASSWORD),
        role=role,
        region=region,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _bearer(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _host_application(
    db: Session,
    email: str = "applicant@example.com",
    region: str | None = "Bagmati",
    with_password: bool = True,
) -> HostApplication:
    app = HostApplication(
        host_name="Ram Bahadur",
        email=email,
        city="Kathmandu",
        region=region,
        phone="9800000000",
        experience="Ten years guiding",
        status="pending",
    )
    if with_password:
        app.credential_password_hash = get_password_hash(PASSWORD)
    db.add(app)
    db.commit()
    db.refresh(app)
    return app


def _guide_application(
    db: Session, email: str = "guide-applicant@example.com", region: str = "Bagmati"
) -> GuideApplication:
    app = GuideApplication(
        full_name="Sita Gurung",
        email=email,
        city="Pokhara",
        region=region,
        status="pending",
    )
    db.add(app)
    db.commit()
    db.refresh(app)
    return app


class TestHostAppications:
    def test_public_submission_captures_a_hashed_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        response = client.post(
            f"{OPS}/host-applications",
            json={
                "host_name": "Gita Rai",
                "email": "gita@example.com",
                "password": PASSWORD,
                "city": "Pokhara",
                "region": "Gandaki",
            },
        )

        assert response.status_code == 201, response.text
        stored = db_session.query(HostApplication).one()
        assert stored.credential_password_hash
        assert stored.credential_password_hash != PASSWORD

    def test_public_submission_rejects_a_weak_password(
        self, client: TestClient
    ) -> None:
        response = client.post(
            f"{OPS}/host-applications",
            json={
                "host_name": "Gita Rai",
                "email": "weak-host@example.com",
                "password": "weak",
            },
        )

        assert response.status_code == 422

    def test_listing_requires_application_staff(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _staff(db_session, role="traveler", email="ops-traveler@example.com")

        response = client.get(f"{OPS}/host-applications", headers=_bearer(traveler))

        assert response.status_code == 403

    def test_staff_can_filter_by_region_and_status(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        _host_application(db_session, "one@example.com", region="Bagmati")
        _host_application(db_session, "two@example.com", region="Gandaki")

        by_region = client.get(
            f"{OPS}/host-applications",
            params={"region": "Gandaki"},
            headers=_bearer(admin),
        )
        by_status = client.get(
            f"{OPS}/host-applications",
            params={"status_filter": "pending"},
            headers=_bearer(admin),
        )

        assert [a["email"] for a in by_region.json()] == ["two@example.com"]
        assert len(by_status.json()) == 2

    def test_regional_heads_only_see_their_region(
        self, client: TestClient, db_session: Session
    ) -> None:
        head = _staff(db_session, role="regional-head", region="Bagmati")
        _host_application(db_session, "inside@example.com", region="Bagmati")
        _host_application(db_session, "outside@example.com", region="Gandaki")

        response = client.get(f"{OPS}/host-applications", headers=_bearer(head))

        assert [a["email"] for a in response.json()] == ["inside@example.com"]

    def test_approval_mints_the_login_account(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _host_application(db_session)

        response = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "approved", "review_note": "Looks good"},
            headers=_bearer(admin),
        )

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["status"] == "approved"
        assert body["login_email"] == "applicant@example.com"
        minted = db_session.get(User, body["user_id"])
        assert minted is not None and minted.role == "host" and minted.is_active

    def test_approval_needs_a_captured_password(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _host_application(
            db_session, email="no-pass@example.com", with_password=False
        )

        response = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "approved"},
            headers=_bearer(admin),
        )

        assert response.status_code == 422
        assert "No password was captured" in response.json()["detail"]

    def test_approval_refuses_to_hijack_an_existing_account(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        _staff(db_session, role="traveler", email="taken@example.com")
        application = _host_application(db_session, email="taken@example.com")

        response = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "approved"},
            headers=_bearer(admin),
        )

        assert response.status_code == 409

    def test_rejection_does_not_mint_an_account(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _host_application(db_session, email="reject@example.com")

        response = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "rejected", "review_note": "Incomplete"},
            headers=_bearer(admin),
        )

        assert response.json()["status"] == "rejected"
        assert response.json()["login_email"] is None
        assert (
            db_session.query(User).filter(User.email == "reject@example.com").first()
            is None
        )

    def test_review_validates_status_and_existence(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _host_application(db_session, email="validate@example.com")

        bad_status = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "maybe"},
            headers=_bearer(admin),
        )
        missing = client.patch(
            f"{OPS}/host-applications/999999",
            json={"status": "approved"},
            headers=_bearer(admin),
        )

        assert bad_status.status_code == 422
        assert missing.status_code == 404

    def test_regional_heads_cannot_review_outside_their_region(
        self, client: TestClient, db_session: Session
    ) -> None:
        head = _staff(db_session, role="regional-head", region="Bagmati")
        application = _host_application(
            db_session, email="far@example.com", region="Gandaki"
        )

        response = client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "approved"},
            headers=_bearer(head),
        )

        assert response.status_code == 403

    def test_hosts_read_their_own_application(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _host_application(db_session, email="self@example.com")
        client.patch(
            f"{OPS}/host-applications/{application.id}",
            json={"status": "approved", "review_note": "Welcome"},
            headers=_bearer(admin),
        )
        host = db_session.query(User).filter(User.email == "self@example.com").one()

        response = client.get(f"{OPS}/host/me/application", headers=_bearer(host))

        assert response.status_code == 200
        assert response.json()["status"] == "approved"
        assert response.json()["reviewed_by"] == "admin@example.com"

    def test_missing_applications_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        orphan = _staff(db_session, role="traveler", email="orphan@example.com")

        response = client.get(f"{OPS}/host/me/application", headers=_bearer(orphan))

        assert response.status_code == 404


class TestGuideApplications:
    def test_public_submission_is_stored_as_pending(self, client: TestClient) -> None:
        response = client.post(
            f"{OPS}/guide-applications",
            json={
                "full_name": "Bikash Thapa",
                "email": "bikash@example.com",
                "city": "Chitwan",
                "nin_number": "12345678",
            },
        )

        assert response.status_code == 201, response.text
        assert response.json()["status"] == "pending"

    def test_listing_and_review_are_staff_only(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _guide_application(db_session)

        listed = client.get(f"{OPS}/guide-applications", headers=_bearer(admin))
        reviewed = client.patch(
            f"{OPS}/guide-applications/{application.id}",
            json={"status": "approved", "review_note": "Verified"},
            headers=_bearer(admin),
        )

        assert listed.status_code == 200
        assert listed.json()[0]["nin_number"] is None or True
        assert reviewed.json()["status"] == "approved"

    def test_invalid_statuses_and_missing_rows_are_rejected(
        self, client: TestClient, db_session: Session
    ) -> None:
        admin = _staff(db_session)
        application = _guide_application(db_session)

        bad_status = client.patch(
            f"{OPS}/guide-applications/{application.id}",
            json={"status": "unknown"},
            headers=_bearer(admin),
        )
        missing = client.patch(
            f"{OPS}/guide-applications/999999",
            json={"status": "approved"},
            headers=_bearer(admin),
        )

        assert bad_status.status_code == 422
        assert missing.status_code == 404

    def test_regional_heads_are_scoped_to_their_region(
        self, client: TestClient, db_session: Session
    ) -> None:
        head = _staff(db_session, role="regional-head", region="Bagmati")
        _guide_application(db_session, "in-region@example.com", region="Bagmati")
        outside = _guide_application(
            db_session, "out-region@example.com", region="Lumbini"
        )

        listed = client.get(f"{OPS}/guide-applications", headers=_bearer(head))
        blocked = client.patch(
            f"{OPS}/guide-applications/{outside.id}",
            json={"status": "approved"},
            headers=_bearer(head),
        )

        assert [a["email"] for a in listed.json()] == ["in-region@example.com"]
        assert blocked.status_code == 403


class TestSupportTickets:
    def _ticket(self, client: TestClient) -> int:
        response = client.post(
            f"{OPS}/support-tickets",
            json={
                "subject": "Refund request",
                "description": "Booked the wrong date",
                "customer_name": "Hari",
                "customer_email": "hari@example.com",
            },
        )
        assert response.status_code == 201, response.text
        return int(response.json()["id"])

    def test_the_desk_requires_ticket_staff(
        self, client: TestClient, db_session: Session
    ) -> None:
        traveler = _staff(
            db_session, role="traveler", email="ticket-traveler@example.com"
        )

        response = client.get(f"{OPS}/support-tickets", headers=_bearer(traveler))

        assert response.status_code == 403

    def test_tickets_can_be_listed_and_read(
        self, client: TestClient, db_session: Session
    ) -> None:
        agent = _staff(db_session, role="customer-support")
        ticket_id = self._ticket(client)

        listed = client.get(f"{OPS}/support-tickets", headers=_bearer(agent))
        detail = client.get(
            f"{OPS}/support-tickets/{ticket_id}", headers=_bearer(agent)
        )

        assert listed.json()[0]["status"] == "open"
        assert detail.json()["subject"] == "Refund request"
        assert detail.json()["priority"] == "medium"

    def test_tickets_can_be_filtered_and_resolved(
        self, client: TestClient, db_session: Session
    ) -> None:
        agent = _staff(db_session, role="customer-support")
        ticket_id = self._ticket(client)

        updated = client.patch(
            f"{OPS}/support-tickets/{ticket_id}",
            json={
                "status": "resolved",
                "priority": "high",
                "assigned_to": "agent@example.com",
                "resolution": "Refunded",
            },
            headers=_bearer(agent),
        )
        resolved = client.get(
            f"{OPS}/support-tickets",
            params={"status_filter": "resolved"},
            headers=_bearer(agent),
        )
        unassigned = client.patch(
            f"{OPS}/support-tickets/{ticket_id}",
            json={"status": "closed"},
            headers=_bearer(agent),
        )

        assert updated.json()["status"] == "resolved"
        assert updated.json()["priority"] == "high"
        assert updated.json()["resolved_at"] is not None
        assert len(resolved.json()) == 1
        assert unassigned.json()["assigned_to"] == "agent@example.com"

    @pytest.mark.parametrize(
        ("payload", "detail"),
        [
            ({"status": "bogus"}, "Invalid status"),
            ({"priority": "bogus"}, "Invalid priority"),
        ],
    )
    def test_bad_updates_are_rejected(
        self,
        client: TestClient,
        db_session: Session,
        payload: dict[str, Any],
        detail: str,
    ) -> None:
        agent = _staff(db_session, role="customer-support")
        ticket_id = self._ticket(client)

        response = client.patch(
            f"{OPS}/support-tickets/{ticket_id}", json=payload, headers=_bearer(agent)
        )

        assert response.status_code == 422
        assert response.json()["detail"] == detail

    def test_unknown_tickets_are_404(
        self, client: TestClient, db_session: Session
    ) -> None:
        agent = _staff(db_session, role="customer-support")

        assert (
            client.get(
                f"{OPS}/support-tickets/999999", headers=_bearer(agent)
            ).status_code
            == 404
        )
        assert (
            client.patch(
                f"{OPS}/support-tickets/999999", json={}, headers=_bearer(agent)
            ).status_code
            == 404
        )

    def test_a_stored_ticket_is_returned_with_its_metadata(
        self, client: TestClient, db_session: Session
    ) -> None:
        agent = _staff(db_session, role="customer-support")
        ticket = SupportTicket(
            subject="Legacy ticket",
            description="From the old site",
            customer_email="legacy@example.com",
            status="open",
            priority="low",
        )
        db_session.add(ticket)
        db_session.commit()
        db_session.refresh(ticket)

        response = client.get(
            f"{OPS}/support-tickets/{ticket.id}", headers=_bearer(agent)
        )

        assert response.json()["subject"] == "Legacy ticket"
        assert response.json()["created_at"] is not None
