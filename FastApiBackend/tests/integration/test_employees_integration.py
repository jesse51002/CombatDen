"""Live integration tests for the employees domain (CRUD + invite status).

Runs against the seeded gym on the shared local Supabase + backend. The
seeded gym owner (``api`` fixture) performs the CRUD; a service-role
``admin_client`` provisions verified auth logins so ``invite_status`` flips
``pending`` → ``active`` and an archived employee's login is proven revoked.

Every created ``gym_employees`` row and every created ``auth.users`` login is
registered on the function-scoped ``created`` fixture and removed on teardown;
the seeded gym's pre-existing rows (owner/admin/front_desk/trainer) are never
mutated — the owner-row edit is asserted to be REJECTED, so nothing is written.

Prereqs (same as the rest of tests/integration): the backend is running on
:8000 and the local Supabase stack is seeded.
"""

from uuid import UUID, uuid4

from tests.integration.conftest import authed_client, sign_in_as
from tests.seed_constants import SEEDED_ADMIN_EMAIL, SEEDED_OWNER_PASSWORD


def _unique_email() -> str:
    """A fresh lowercase email that can't collide with the seed or a prior run."""
    return f"itest-emp-{uuid4().hex[:12]}@example.com"


def _create_employee(
    api,
    gym_id: str,
    created,
    *,
    email: str,
    employee_type: str = "front_desk",
    first_name: str = "Test",
    last_name: str = "Employee",
) -> dict:
    """POST an employee, track it for cleanup, and return the response body."""
    resp = api.post(
        f"/api/v1/employees/{gym_id}",
        json={
            "employee_type": employee_type,
            "first_name": first_name,
            "last_name": last_name,
            "email": email,
        },
    )
    resp.raise_for_status()
    body = resp.json()
    created.track_employee(UUID(body["employee_id"]))
    return body


def _roster(api, gym_id: str) -> list[dict]:
    resp = api.get(f"/api/v1/employees/{gym_id}")
    resp.raise_for_status()
    return resp.json()["employees"]


def test_create_is_pending_then_active_after_login_provisioned(
    api, gym_id, created, admin_client
):
    """A created employee with an email but no verified account is
    ``pending``; once a verified ``auth.users`` account exists for that email,
    the same row reads ``active``."""
    email = _unique_email()
    body = _create_employee(api, gym_id, created, email=email)
    assert body["invite_status"] == "pending"
    employee_id = body["employee_id"]

    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    match = next(
        e for e in _roster(api, gym_id) if e["employee_id"] == employee_id
    )
    assert match["invite_status"] == "active"


def test_duplicate_email_same_gym_conflicts(api, gym_id, created):
    """A second employee with an email already used at the gym is a 409."""
    email = _unique_email()
    _create_employee(api, gym_id, created, email=email)

    resp = api.post(
        f"/api/v1/employees/{gym_id}",
        json={
            "employee_type": "trainer",
            "first_name": "Dup",
            "last_name": "Licate",
            "email": email,
        },
    )
    assert resp.status_code == 409


def test_update_employee_fields(api, gym_id, created):
    """A normal (non-owner) employee edit succeeds and echoes the change."""
    body = _create_employee(
        api, gym_id, created, email=_unique_email(), first_name="Before"
    )
    resp = api.put(
        f"/api/v1/employees/{gym_id}/{body['employee_id']}",
        json={"data": {"first_name": "After"}},
    )
    assert resp.status_code == 200
    assert resp.json()["first_name"] == "After"


def test_admin_cannot_edit_owner_row(api, gym_id):
    """The owner row may be edited only by the owner — an admin editing it is
    a 403 (and nothing on the seeded owner row is mutated)."""
    owner = next(e for e in _roster(api, gym_id) if e["employee_type"] == "owner")

    admin_api = authed_client(
        sign_in_as(SEEDED_ADMIN_EMAIL, SEEDED_OWNER_PASSWORD)
    )
    try:
        resp = admin_api.put(
            f"/api/v1/employees/{gym_id}/{owner['employee_id']}",
            json={"data": {"first_name": "Hacked"}},
        )
    finally:
        admin_api.close()
    assert resp.status_code == 403


def test_archive_removes_from_roster_and_revokes_login(
    api, gym_id, created, admin_client
):
    """DELETE soft-archives: the employee drops out of the roster, and the
    (now-archived) login is denied a subsequent staff call — access dies
    because every role check filters ``archived_at IS NULL``."""
    email = _unique_email()
    body = _create_employee(
        api, gym_id, created, email=email, employee_type="front_desk"
    )
    employee_id = body["employee_id"]

    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    staff_api = authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))
    try:
        # front_desk (STAFF) can read the members list BEFORE archiving.
        before = staff_api.post(
            "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
        )
        assert before.status_code == 200

        arch = api.delete(f"/api/v1/employees/{gym_id}/{employee_id}")
        assert arch.status_code == 204

        # Gone from the roster.
        assert all(
            e["employee_id"] != employee_id for e in _roster(api, gym_id)
        )

        # Same JWT, now-archived row → the staff call is revoked (403).
        after = staff_api.post(
            "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
        )
        assert after.status_code == 403
    finally:
        staff_api.close()
