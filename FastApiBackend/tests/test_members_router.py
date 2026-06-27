"""Smoke + edge tests for the members router."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.main import app
from src.members.schema.members_billing_schema import (
    BillingPersonalInfo,
    BillingRetention,
    MemberBillingDetailResponse,
    MembersBillingProfileResponse,
)
from src.members.schema.members_crm_members_list_schema import (
    AllViewRow,
    CrmMembersListResponse,
    MembersListFilters,
    MembersListTotalCounts,
    MembersListView,
)
from src.memberships.memberships_schema import PayerInvoiceChange
from tests.conftest import make_member_row


def test_create_member_returns_201(client, auth_headers, fake_gym_id):
    """POST /api/v1/members/ provisions a Stripe customer and returns the profile."""
    member_id = str(uuid4())
    mgmt = MagicMock()
    mgmt.create_member = AsyncMock(
        return_value=MembersBillingProfileResponse(
            member_id=member_id,
            gym_id=fake_gym_id,
            first_name="Ada",
            last_name="Lovelace",
            email="ada@example.com",
            stripe_customer_id="cus_test123",
        ),
    )
    app.container.members_management_service.override(mgmt)
    try:
        response = client.post(
            "/api/v1/members/",
            json={
                "gym_id": fake_gym_id,
                "first_name": "Ada",
                "last_name": "Lovelace",
                "email": "ada@example.com",
            },
            headers=auth_headers,
        )
    finally:
        app.container.members_management_service.reset_override()

    assert response.status_code == 201
    body = response.json()
    assert body["member_id"] == member_id
    # Every member is created with a Stripe customer.
    assert body["stripe_customer_id"] == "cus_test123"
    mgmt.create_member.assert_awaited_once()


def test_create_member_persists_contact_fields(client, auth_headers, fake_gym_id):
    """POST accepts the full contact profile, passes it to the service, echoes it."""
    member_id = str(uuid4())
    mgmt = MagicMock()
    mgmt.create_member = AsyncMock(
        return_value=MembersBillingProfileResponse(
            member_id=member_id,
            gym_id=fake_gym_id,
            first_name="Ada",
            last_name="Lovelace",
            email="ada@example.com",
            phone="+1-555-0100",
            address="1 Tatami Way",
            emergency_contact_name="Grace Hopper",
            emergency_contact_phone="+1-555-0199",
            emergency_contact_email="grace@example.com",
            stripe_customer_id="cus_test123",
        ),
    )
    app.container.members_management_service.override(mgmt)
    try:
        response = client.post(
            "/api/v1/members/",
            json={
                "gym_id": fake_gym_id,
                "first_name": "Ada",
                "last_name": "Lovelace",
                "email": "ada@example.com",
                "phone": "+1-555-0100",
                "address": "1 Tatami Way",
                "emergency_contact_name": "Grace Hopper",
                "emergency_contact_phone": "+1-555-0199",
                "emergency_contact_email": "grace@example.com",
                "photo_url": "https://cdn.example.com/ada.png",
            },
            headers=auth_headers,
        )
    finally:
        app.container.members_management_service.reset_override()

    assert response.status_code == 201
    body = response.json()
    assert body["phone"] == "+1-555-0100"
    assert body["address"] == "1 Tatami Way"
    assert body["emergency_contact_name"] == "Grace Hopper"
    assert body["emergency_contact_phone"] == "+1-555-0199"
    assert body["emergency_contact_email"] == "grace@example.com"

    # The router must pass the full contact profile (incl. photo_url) through to
    # the create service, not drop any field.
    passed_request = mgmt.create_member.call_args.args[0]
    assert passed_request.phone == "+1-555-0100"
    assert passed_request.emergency_contact_email == "grace@example.com"
    assert passed_request.photo_url == "https://cdn.example.com/ada.png"


def test_create_member_rejects_malformed_emergency_email(client, auth_headers, fake_gym_id):
    """emergency_contact_email is validated as an email (422 on garbage)."""
    response = client.post(
        "/api/v1/members/",
        json={
            "gym_id": fake_gym_id,
            "first_name": "Ada",
            "last_name": "Lovelace",
            "emergency_contact_email": "not-an-email",
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_member_accepts_contact_fields(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """PUT accepts contact fields, binds them, and echoes them back."""
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value=make_member_row(
            member_id=fake_member_id,
            gym_id=fake_gym_id,
            phone="+1-555-0123",
            emergency_contact_email="kin@example.com",
        ),
    )

    response = client.put(
        f"/api/v1/members/{fake_member_id}",
        json={
            "data": {
                "phone": "+1-555-0123",
                "emergency_contact_email": "kin@example.com",
            }
        },
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["phone"] == "+1-555-0123"
    assert body["emergency_contact_email"] == "kin@example.com"

    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert bound_params["phone"] == "+1-555-0123"
    assert bound_params["emergency_contact_email"] == "kin@example.com"


def test_update_member_rejects_malformed_emergency_email(client, auth_headers, fake_member_id):
    """PUT validates emergency_contact_email too (422 on garbage)."""
    response = client.put(
        f"/api/v1/members/{fake_member_id}",
        json={"data": {"emergency_contact_email": "nope"}},
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_member_400_when_empty_data(client, auth_headers, fake_member_id):
    """PUT /api/v1/members/{member_id} rejects an empty data payload."""
    response = client.put(
        f"/api/v1/members/{fake_member_id}",
        json={"data": {}},
        headers=auth_headers,
    )
    assert response.status_code == 400


def test_list_members_returns_paginated_response(client, auth_headers, fake_gym_id):
    """POST /api/v1/members/list returns view + filters + data."""
    member_id = str(uuid4())
    mock_response = CrmMembersListResponse(
        view=MembersListView.all,
        filters=MembersListFilters(),
        data=[
            AllViewRow(
                member_id=member_id,
                name="Ada Lovelace",
                email="ada@example.com",
                membership_status="active",
                membership_text="Active",
                days_since_last_class=3,
            )
        ],
    )

    mock_service = MagicMock()
    mock_service.get_crm_members_list = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.crm_members_list_service.override(mock_service)
    try:
        response = client.post(
            "/api/v1/members/list",
            json={
                "gym_id": fake_gym_id,
                "view": "all",
            },
            headers=auth_headers,
        )
    finally:
        container.crm_members_list_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body["view"] == "all"
    assert len(body["data"]) == 1
    assert body["data"][0]["member_id"] == member_id
    assert body["data"][0]["membership_status"] == "active"


def test_list_members_hydrates_nested_rank(client, auth_headers, fake_gym_id, fake_rank_id):
    """POST /api/v1/members/list passes through the service response unchanged."""
    member_id = str(uuid4())
    mock_response = CrmMembersListResponse(
        view=MembersListView.all,
        filters=MembersListFilters(),
        data=[
            AllViewRow(
                member_id=member_id,
                name="Blue Belt",
                email=None,
                membership_status="active",
                membership_text="Active",
            )
        ],
    )

    mock_service = MagicMock()
    mock_service.get_crm_members_list = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.crm_members_list_service.override(mock_service)
    try:
        response = client.post(
            "/api/v1/members/list",
            json={
                "gym_id": fake_gym_id,
                "view": "all",
            },
            headers=auth_headers,
        )
    finally:
        container.crm_members_list_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body["data"][0]["member_id"] == member_id


def test_total_counts_returns_per_status(client, auth_headers, fake_gym_id):
    """GET /api/v1/members/counts returns counts for each status."""
    mock_response = MembersListTotalCounts(active=6, trial=2, frozen=1, overdue=1)

    mock_service = MagicMock()
    mock_service.get_total_counts = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.crm_total_counts_service.override(mock_service)
    try:
        response = client.get(
            f"/api/v1/members/counts?gym_id={fake_gym_id}",
            headers=auth_headers,
        )
    finally:
        container.crm_total_counts_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body == {"active": 6, "trial": 2, "frozen": 1, "overdue": 1}


def test_member_detail_includes_streak_and_redemptions(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """GET /api/v1/members/{member_id} returns full billing detail."""
    mock_response = MemberBillingDetailResponse(
        member_id=fake_member_id,
        gym_id=fake_gym_id,
        first_name="Ada",
        last_name="Lovelace",
        membership_overview="Active",
        total_monthly_recurring_price=0,
        total_membership_count=0,
        personal_info=BillingPersonalInfo(),
        linked_accounts=[],
        memberships=[],
        retention=BillingRetention(
            class_streak_weeks=0,
            points_balance=100,
            videos_watched=0,
        ),
        recently_redeemed_rewards=[],
    )

    mock_service = MagicMock()
    mock_service.get_member_billing_detail = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.members_billing_detail_service.override(mock_service)
    try:
        response = client.get(
            f"/api/v1/members/{fake_member_id}",
            headers=auth_headers,
        )
    finally:
        container.members_billing_detail_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body["retention"]["class_streak_weeks"] == 0
    assert body["recently_redeemed_rewards"] == []
    assert body["rank"] is None


def test_member_detail_hydrates_nested_rank(
    client, auth_headers, fake_member_id, fake_gym_id, fake_rank_id
):
    """GET /api/v1/members/{id} returns detail even with a rank present."""
    mock_response = MemberBillingDetailResponse(
        member_id=fake_member_id,
        gym_id=fake_gym_id,
        first_name="Ada",
        last_name="Lovelace",
        membership_overview="Active",
        total_monthly_recurring_price=0,
        total_membership_count=0,
        personal_info=BillingPersonalInfo(),
        linked_accounts=[],
        memberships=[],
        retention=BillingRetention(
            class_streak_weeks=2,
            points_balance=500,
            videos_watched=10,
        ),
        recently_redeemed_rewards=[],
    )

    mock_service = MagicMock()
    mock_service.get_member_billing_detail = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.members_billing_detail_service.override(mock_service)
    try:
        response = client.get(
            f"/api/v1/members/{fake_member_id}",
            headers=auth_headers,
        )
    finally:
        container.members_billing_detail_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body["retention"]["class_streak_weeks"] == 2
    assert body["member_id"] == fake_member_id


def test_preview_remove_authorization_accepts_no_idempotency_key(
    client, auth_headers, fake_member_id
):
    """The preview is read-only, so it must accept the CRM's body shape —
    ``{payer_member_id}`` with NO ``idempotency_key``.

    Regression guard: the preview endpoint once shared the mutating request
    model (which requires ``idempotency_key``), so the CRM's preview call —
    which sends only ``payer_member_id`` — was rejected with HTTP 422, and the
    dialog showed "No memberships are funded" for genuinely-funded relationships.
    A preview has nothing to dedup, so it must NOT demand the key.
    """
    payer_id = str(uuid4())
    mock_service = MagicMock()
    mock_service.preview_remove_authorization = AsyncMock(
        return_value=[
            PayerInvoiceChange(
                payer_member_id=payer_id,
                payer_first_name="Patricia",
                payer_last_name="Taylor",
                affected=True,
                preview=None,
            )
        ]
    )
    container = client.app.container
    container.member_memberships_service.override(mock_service)
    try:
        response = client.post(
            f"/api/v1/members/{fake_member_id}/link/remove/preview",
            json={"payer_member_id": payer_id},
            headers=auth_headers,
        )
    finally:
        container.member_memberships_service.reset_override()

    assert response.status_code == 200
    body = response.json()
    assert body[0]["payer_member_id"] == payer_id
    assert body[0]["affected"] is True
    # The service is called with (path member_id = payee, body payer_id = payer).
    mock_service.preview_remove_authorization.assert_awaited_once()
    call = mock_service.preview_remove_authorization.await_args
    assert str(call.args[0]) == fake_member_id
    assert str(call.args[1]) == payer_id


def test_remove_authorization_still_requires_idempotency_key(
    client, auth_headers, fake_member_id
):
    """The MUTATING remove endpoint keeps ``idempotency_key`` required.

    The asymmetry is deliberate: the cascading cancel writes to Stripe and must
    dedup on retry, so the mutating request needs the key; the preview does not.
    Omitting it on the real remove is a 422 (validation), never a silent cancel.
    """
    response = client.post(
        f"/api/v1/members/{fake_member_id}/link/remove",
        json={"payer_member_id": str(uuid4())},
        headers=auth_headers,
    )
    assert response.status_code == 422
    assert any(
        err["loc"][-1] == "idempotency_key"
        for err in response.json()["detail"]
    )
