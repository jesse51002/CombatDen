"""Unit tests for the role-set authorization core in ``src/shared/auth.py``.

Exercises the real ``Auth`` class against a MOCKED ``SupabaseClient`` — the
PostgREST builder chain (``.from_().select().eq()...maybe_single().execute()``)
is faked so no network / DB is touched. Covers ``verify_roles`` (matched role
returned, 403 on no match, 401 on missing email, email lowercased before the
query, allowed-role filter), ``verify_staff_principal``, and the three
branches of ``verify_can_view_member`` (self, family, staff).
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.shared.auth import OWNER_ADMIN, STAFF, Auth


def _builder(data: object) -> MagicMock:
    """A PostgREST query-builder double.

    Every chained filter method returns the same builder, and the terminal
    (awaited) ``.execute()`` resolves to an object with a ``.data`` attr.
    """
    builder = MagicMock()
    for method in ("select", "eq", "in_", "is_", "maybe_single", "limit"):
        getattr(builder, method).return_value = builder
    response = MagicMock()
    response.data = data
    builder.execute = AsyncMock(return_value=response)
    return builder


def _supabase(tables: dict[str, object]) -> tuple[MagicMock, dict]:
    """Build a ``SupabaseClient`` double.

    ``tables`` maps a table name to the ``.data`` its query chain resolves to.
    ``client.from_(name)`` returns that table's builder (a table not in the
    map raises ``KeyError`` — surfacing an unexpected extra query loudly).

    Returns ``(supabase, builders)`` so a test can inspect the filter calls.
    """
    builders = {name: _builder(data) for name, data in tables.items()}
    supabase = MagicMock()
    supabase.client.from_.side_effect = lambda name: builders[name]
    return supabase, builders


# ── verify_roles ──────────────────────────────────────────────────


async def test_verify_roles_returns_matched_role_and_filters() -> None:
    """A non-archived row whose type is in ``allowed`` and whose email
    matches returns the matched ``employee_type``; the query filters on the
    lowercased email, the gym, the allowed roles, and archived IS NULL."""
    gym_id = uuid4()
    supabase, builders = _supabase(
        {
            "gym_employees": {
                "employee_id": str(uuid4()),
                "employee_type": "front_desk",
            }
        }
    )
    auth = Auth(supabase)

    result = await auth.verify_roles(
        gym_id, {"email": "Owner@Test.com"}, STAFF
    )

    assert result is EmployeeType.front_desk
    b = builders["gym_employees"]
    eq_calls = {c.args for c in b.eq.call_args_list}
    assert ("gym_id", str(gym_id)) in eq_calls
    # Email is lowercased BEFORE the query.
    assert ("email", "owner@test.com") in eq_calls
    b.is_.assert_called_once_with("archived_at", "null")
    (col, roles) = b.in_.call_args.args
    assert col == "employee_type"
    assert set(roles) == {r.value for r in STAFF}


async def test_verify_roles_403_when_no_matching_row() -> None:
    """No matching non-archived row → 403 (role mismatch / not an employee)."""
    supabase, _ = _supabase({"gym_employees": None})
    auth = Auth(supabase)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_roles(uuid4(), {"email": "a@b.com"}, OWNER_ADMIN)
    assert exc.value.status_code == 403


async def test_verify_roles_401_when_no_email_and_no_query() -> None:
    """A payload with no ``email`` claim is a 401, before any DB query."""
    supabase, _ = _supabase(
        {
            "gym_employees": {
                "employee_id": str(uuid4()),
                "employee_type": "owner",
            }
        }
    )
    auth = Auth(supabase)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_roles(uuid4(), {}, OWNER_ADMIN)
    assert exc.value.status_code == 401
    supabase.client.from_.assert_not_called()


# ── verify_staff_principal ────────────────────────────────────────


async def test_verify_staff_principal_passes_for_front_desk() -> None:
    """A front_desk row (in ``STAFF``) at any gym passes the gym-agnostic
    staff gate; the query is limited and filters the allowed roles."""
    supabase, builders = _supabase(
        {"gym_employees": [{"employee_id": str(uuid4())}]}
    )
    auth = Auth(supabase)

    result = await auth.verify_staff_principal({"email": "fd@test.com"}, STAFF)

    assert result is None
    b = builders["gym_employees"]
    b.limit.assert_called_once_with(1)
    b.is_.assert_called_once_with("archived_at", "null")
    (col, roles) = b.in_.call_args.args
    assert col == "employee_type"
    assert set(roles) == {r.value for r in STAFF}


async def test_verify_staff_principal_403_when_none() -> None:
    """No staff row anywhere → 403."""
    supabase, _ = _supabase({"gym_employees": []})
    auth = Auth(supabase)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_staff_principal({"email": "nobody@test.com"}, STAFF)
    assert exc.value.status_code == 403


# ── verify_can_view_member ────────────────────────────────────────


async def test_view_member_self_branch_no_staff_query() -> None:
    """When the member row's email equals the caller's, access is granted
    immediately — NO gym_employees staff query is issued."""
    member_id = uuid4()
    supabase, builders = _supabase(
        {"members": {"email": "caller@test.com", "gym_id": str(uuid4())}}
    )
    auth = Auth(supabase)

    await auth.verify_can_view_member(member_id, {"email": "Caller@Test.com"})

    queried = [c.args[0] for c in supabase.client.from_.call_args_list]
    assert queried == ["members"]  # only the member lookup, no staff query
    builders["members"].eq.assert_called_once_with("member_id", str(member_id))


async def test_view_member_family_branch_parent_email_on_child_row() -> None:
    """The family case: the caller is a parent whose email is carried on a
    DIFFERENT member's (their child's) row — still the self/email branch, so
    no staff query runs."""
    child_id = uuid4()
    supabase, _ = _supabase(
        {"members": {"email": "parent@test.com", "gym_id": str(uuid4())}}
    )
    auth = Auth(supabase)

    await auth.verify_can_view_member(child_id, {"email": "parent@test.com"})

    queried = [c.args[0] for c in supabase.client.from_.call_args_list]
    assert queried == ["members"]


async def test_view_member_staff_branch_runs_verify_roles() -> None:
    """When the caller is NOT the member, access falls through to a
    ``verify_roles`` check on the member's gym, scoped to ``staff_roles``."""
    member_id = uuid4()
    gym_id = uuid4()
    supabase, builders = _supabase(
        {
            "members": {"email": "someone@test.com", "gym_id": str(gym_id)},
            "gym_employees": {
                "employee_id": str(uuid4()),
                "employee_type": "admin",
            },
        }
    )
    auth = Auth(supabase)

    await auth.verify_can_view_member(
        member_id, {"email": "staff@test.com"}, staff_roles=OWNER_ADMIN
    )

    queried = [c.args[0] for c in supabase.client.from_.call_args_list]
    assert queried == ["members", "gym_employees"]
    emp = builders["gym_employees"]
    eq_calls = {c.args for c in emp.eq.call_args_list}
    assert ("gym_id", str(gym_id)) in eq_calls
    (col, roles) = emp.in_.call_args.args
    assert set(roles) == {r.value for r in OWNER_ADMIN}


async def test_view_member_404_when_member_missing() -> None:
    """A missing member row is a 404 before the email/staff branch."""
    supabase, _ = _supabase({"members": None})
    auth = Auth(supabase)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_can_view_member(uuid4(), {"email": "x@y.com"})
    assert exc.value.status_code == 404
