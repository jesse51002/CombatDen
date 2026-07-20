"""Live role-access-matrix integration tests.

Signs in as each seeded role (owner / admin / front_desk / trainer) and asserts
a REPRESENTATIVE slice of the route authorization matrix returns 200 vs 403,
proving the role-set guards (``verify_roles`` / ``verify_gym_admin_or_owner`` /
``verify_gym_employee_for_member`` / ``verify_can_view_member``) admit exactly
the intended roles.

Deliberately lightweight: 200s are cheap READS and 403s short-circuit inside
the handler BEFORE any write (the request body is still schema-valid so the
guard — not Pydantic — is what rejects). It reuses the seeded gym + a seeded
member; it creates nothing, so there is nothing to clean up.

Prereqs (same as the rest of tests/integration): the backend is running on
:8000 and the local Supabase stack is seeded.
"""

from uuid import uuid4

import pytest

from tests.integration.conftest import authed_client, sign_in_as
from tests.seed_constants import (
    SEEDED_ADMIN_EMAIL,
    SEEDED_FRONT_DESK_EMAIL,
    SEEDED_OWNER_EMAIL,
    SEEDED_OWNER_PASSWORD,
    SEEDED_TRAINER_EMAIL,
)


def _client(email: str):
    return authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))


@pytest.fixture(scope="module")
def owner_api():
    c = _client(SEEDED_OWNER_EMAIL)
    yield c
    c.close()


@pytest.fixture(scope="module")
def admin_api():
    c = _client(SEEDED_ADMIN_EMAIL)
    yield c
    c.close()


@pytest.fixture(scope="module")
def front_desk_api():
    c = _client(SEEDED_FRONT_DESK_EMAIL)
    yield c
    c.close()


@pytest.fixture(scope="module")
def trainer_api():
    c = _client(SEEDED_TRAINER_EMAIL)
    yield c
    c.close()


@pytest.fixture(scope="module")
def seeded_member_id(owner_api, gym_id: str) -> str:
    """A member id from the seeded gym (needed for the member-scoped guards,
    which resolve the member's gym BEFORE the role check)."""
    resp = owner_api.post(
        "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
    )
    resp.raise_for_status()
    rows = resp.json()["data"]
    if not rows:
        pytest.skip("No seeded members to target")
    return rows[0]["member_id"]


@pytest.fixture(scope="module")
def seeded_rank_id(owner_api, gym_id: str) -> str:
    """A rank id from the seeded gym's ladder (needed for the rank-detail
    reads, which derive gym_id from the rank BEFORE the role check)."""
    resp = owner_api.get("/api/v1/ranks/", params={"gym_id": gym_id})
    resp.raise_for_status()
    items = resp.json()["items"]
    if not items:
        pytest.skip("No seeded ranks to target")
    return items[0]["rank_id"]


# ── GET /api/v1/gyms/ — every role sees the seeded gym ─────────────


def test_gyms_list_returns_seeded_gym_for_all_roles(
    owner_api, admin_api, front_desk_api, trainer_api, gym_id: str
):
    for label, api in (
        ("owner", owner_api),
        ("admin", admin_api),
        ("front_desk", front_desk_api),
        ("trainer", trainer_api),
    ):
        resp = api.get("/api/v1/gyms/")
        assert resp.status_code == 200, f"{label}: {resp.text}"
        gym_ids = {g["gym_id"] for g in resp.json()}
        assert gym_id in gym_ids, f"{label} does not see the seeded gym"


# ── front_desk (STAFF) — allowed ──────────────────────────────────


def test_front_desk_can_list_members(front_desk_api, gym_id: str):
    resp = front_desk_api.post(
        "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
    )
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_member_invoices(front_desk_api, seeded_member_id):
    """A cheap money-read: front_desk (STAFF) may view a member's invoices."""
    resp = front_desk_api.get(f"/api/v1/members/{seeded_member_id}/invoices")
    assert resp.status_code == 200, resp.text


# ── front_desk (STAFF) — forbidden (OWNER_ADMIN-only) ─────────────


def test_front_desk_cannot_create_plan(front_desk_api, gym_id: str):
    """Plan create is owner/admin only — a schema-valid body still 403s."""
    resp = front_desk_api.post(
        "/api/v1/membership_plans/",
        json={
            "gym_id": gym_id,
            "plan_name": "Matrix Test Plan",
            "plan_type": "recurring",
            "duration_amount": 1,
            "duration_unit": "month",
            "price": 5000,
        },
    )
    assert resp.status_code == 403, resp.text


def test_front_desk_cannot_reprice_membership(front_desk_api, seeded_member_id):
    """Reprice is owner/admin only. A REAL member id is used so the member's
    gym resolves and the role check (not a 404) is what returns 403."""
    resp = front_desk_api.put(
        "/api/v1/member_memberships/price",
        json={
            "item_id": str(uuid4()),
            "member_id": seeded_member_id,
            "idempotency_key": str(uuid4()),
        },
    )
    assert resp.status_code == 403, resp.text


def test_front_desk_cannot_adjust_points(front_desk_api, seeded_member_id):
    """Manual points adjustment is owner/admin only."""
    resp = front_desk_api.post(
        f"/api/v1/members/{seeded_member_id}/points", json={"amount": 10}
    )
    assert resp.status_code == 403, resp.text


# ── front_desk (STAFF) — allowed: ranks reads ─────────────────────


def test_front_desk_can_list_ranks(front_desk_api, gym_id: str):
    resp = front_desk_api.get("/api/v1/ranks/", params={"gym_id": gym_id})
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_rank_enabled(front_desk_api, gym_id: str):
    resp = front_desk_api.get(
        "/api/v1/ranks/enabled", params={"gym_id": gym_id}
    )
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_ready_to_promote(front_desk_api, gym_id: str):
    resp = front_desk_api.get(
        "/api/v1/ranks/ready-to-promote", params={"gym_id": gym_id}
    )
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_members_in_rank(front_desk_api, seeded_rank_id):
    resp = front_desk_api.get(f"/api/v1/ranks/{seeded_rank_id}/members")
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_sub_rank_counts(front_desk_api, seeded_rank_id):
    resp = front_desk_api.get(
        f"/api/v1/ranks/{seeded_rank_id}/sub-rank-counts"
    )
    assert resp.status_code == 200, resp.text


def test_front_desk_can_read_rank_detail(front_desk_api, seeded_rank_id):
    resp = front_desk_api.get(f"/api/v1/ranks/{seeded_rank_id}")
    assert resp.status_code == 200, resp.text


# ── front_desk (STAFF) — forbidden: ranks write (OWNER_ADMIN-only) ─


def test_front_desk_cannot_create_rank(front_desk_api, gym_id: str):
    """Rank create is owner/admin only — a schema-valid body still 403s."""
    resp = front_desk_api.post(
        "/api/v1/ranks/",
        json={
            "gym_id": gym_id,
            "main_rank_num_order": 9999,
            "name": "Matrix Test Rank",
            "classes_to_next_major": 10,
        },
    )
    assert resp.status_code == 403, resp.text


def test_front_desk_cannot_promote_member(
    front_desk_api, gym_id: str, seeded_member_id
):
    """Promote is owner/admin only — a schema-valid body still 403s."""
    resp = front_desk_api.post(
        "/api/v1/ranks/promote-member",
        json={"gym_id": gym_id, "member_id": seeded_member_id},
    )
    assert resp.status_code == 403, resp.text


# ── trainer (ALL_EMPLOYEES reads) — allowed ───────────────────────


def test_trainer_can_read_class_instances(trainer_api, gym_id: str):
    resp = trainer_api.get(
        "/api/v1/classes/instances",
        params={
            "gym_id": gym_id,
            "start_date": "2026-01-01",
            "end_date": "2026-12-31",
        },
    )
    assert resp.status_code == 200, resp.text


def test_trainer_can_read_checkin_attendees(trainer_api, gym_id: str):
    """The attendees roster is trainer-visible (ALL_EMPLOYEES). A nonexistent
    occurrence at the trainer's own gym resolves to an empty roster (200), not
    a 403 — the caller IS an employee of the gym."""
    resp = trainer_api.get(
        "/api/v1/checkin/attendees",
        params={
            "gym_id": gym_id,
            "class_id": str(uuid4()),
            "occurrence_date": "2999-12-31",
            "occurrence_time": "00:00:00",
        },
    )
    assert resp.status_code == 200, resp.text


# ── trainer — forbidden (STAFF-only) ──────────────────────────────


def test_trainer_cannot_list_members(trainer_api, gym_id: str):
    resp = trainer_api.post(
        "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
    )
    assert resp.status_code == 403, resp.text


def test_trainer_cannot_create_member(trainer_api, gym_id: str):
    """Member create is STAFF-only — a schema-valid body still 403s (before
    any Stripe customer is provisioned)."""
    resp = trainer_api.post(
        "/api/v1/members/",
        json={
            "gym_id": gym_id,
            "first_name": "Nope",
            "last_name": "Trainer",
            "email": f"itest-{uuid4().hex[:12]}@example.com",
        },
    )
    assert resp.status_code == 403, resp.text
