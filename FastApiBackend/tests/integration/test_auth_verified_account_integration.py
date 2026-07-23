"""Live integration proof that an UNVERIFIED auth account gets nothing.

Identity is the verified email claim matched against a ``gym_employees``
row. A matching row is deliberately not enough: every identity-resolving
query also requires ``auth.users.email_confirmed_at IS NOT NULL``, so signing
up as an existing employee's address without ever proving control of that
inbox must grant zero access.

The test proves that with ONE unchanged JWT:

1. Create an employee row + a CONFIRMED auth account for its email, sign in.
2. Calls succeed (gym-scoped staff read + the gym list).
3. Flip ``email_confirmed_at`` to NULL — nothing else changes; the token is
   the same, still unexpired.
4. The SAME token is now 403 on the gym-scoped read and the gym has vanished
   from its gym list.
5. Re-confirming restores access — which pins the cause on the DB predicate,
   not on token expiry or a signed-out session.

Everything created (the employee row, the auth user) is registered on the
function-scoped ``created`` fixture and removed on teardown; the seeded gym's
own rows are never touched.

Prereqs (same as the rest of tests/integration): the backend is running at
``BACKEND_BASE_URL`` and the local Supabase stack is seeded. NOTE the backend
is a SEPARATE process — it must be running THIS branch's code for the 403 leg
to mean anything.
"""

from uuid import UUID, uuid4

from tests.helpers.db_writes import set_auth_email_confirmed
from tests.integration.conftest import authed_client, sign_in_as
from tests.seed_constants import SEEDED_OWNER_PASSWORD


def _unique_email() -> str:
    """A fresh lowercase email that can't collide with the seed or a prior run."""
    return f"itest-verif-{uuid4().hex[:12]}@example.com"


def _gyms_list(client) -> tuple[int, set[str]]:
    """``(status, gym_ids)`` for ``GET /api/v1/gyms/``.

    The route runs ``verify_verified_account``, so an unverified caller gets a
    403 rather than a 200 carrying an empty list — an explicit answer beats a
    silently empty one. The ids are only meaningful on a 200.
    """
    resp = client.get("/api/v1/gyms/")
    if resp.status_code != 200:
        return resp.status_code, set()
    return 200, {g["gym_id"] for g in resp.json()}


def _members_list_status(client, gym_id: str) -> int:
    """Status of a cheap gym-scoped STAFF read (front desk is in ``STAFF``)."""
    return client.post(
        "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
    ).status_code


async def test_unverified_account_loses_access_with_the_same_jwt(
    api, gym_id: str, created, admin_client, db_pool
) -> None:
    """An employee row + a matching JWT is not access — the auth account must
    be CONFIRMED. Un-confirming it 403s the very same token."""
    email = _unique_email()

    resp = api.post(
        f"/api/v1/employees/{gym_id}",
        json={
            "employee_type": "front_desk",
            "first_name": "Verify",
            "last_name": "Guard",
            "email": email,
        },
    )
    assert resp.status_code in (200, 201), resp.text
    created.track_employee(UUID(resp.json()["employee_id"]))

    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    client = authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))
    try:
        # 1. Verified: the gym-scoped staff read passes and the gym is listed.
        assert _members_list_status(client, gym_id) == 200
        status, gym_ids = _gyms_list(client)
        assert status == 200
        assert gym_id in gym_ids

        # 2. Un-confirm the inbox. The JWT is untouched and still unexpired.
        await set_auth_email_confirmed(db_pool, user_id, confirmed=False)

        assert _members_list_status(client, gym_id) == 403
        # 403, not an empty 200: the route resolves identity up front via
        # verify_verified_account rather than leaning on the SQL predicate.
        assert _gyms_list(client)[0] == 403

        # 3. Re-confirm: access returns. Proves the 403 came from the
        #    verified-account predicate, not from the token going stale.
        await set_auth_email_confirmed(db_pool, user_id, confirmed=True)

        assert _members_list_status(client, gym_id) == 200
        status, gym_ids = _gyms_list(client)
        assert status == 200
        assert gym_id in gym_ids
    finally:
        client.close()
