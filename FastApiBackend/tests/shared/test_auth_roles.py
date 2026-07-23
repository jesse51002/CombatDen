"""Unit tests for the role-set authorization core in ``src/shared/auth.py``.

Exercises the real ``Auth`` class against a MOCKED ``DirectDatabasePool`` —
the ``async with pool.session()`` context and ``session.execute`` are faked so
no network / DB is touched, and the tests can assert the exact SQL file and
bind parameters each check issues.

Covers ``verify_roles`` (matched role returned, 403 on no match, 401 on
missing email, email lowercased before the query, allowed-role array bound),
``verify_staff_principal``, ``verify_verified_account``, and
``verify_member_self`` (self / family / unverified / wrong-gym / 404).

Every identity-resolving query now also pins its confirmed-account ``EXISTS``
to the CALLER's own ``auth.users`` id (the JWT ``sub``), so each real ``Auth``
call carries a ``sub`` claim (``_CALLER_ID``) and the checks bind it as
``caller_id``.

The last test is a DRIFT GUARD: it reads the identity-resolving ``.sql``
files off disk and fails if any loses its ``email_confirmed_at IS NOT NULL``
predicate — the single line standing between a signed-up-as-owner@ stranger
and full gym access — or its ``u.id = CAST(:caller_id AS UUID)`` caller pin.
"""

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.shared import SQL_DIR
from src.shared.auth import OWNER_ADMIN, STAFF, Auth

# The identity-resolving queries. Every one of these hands a caller a role,
# an employee_id, or a "you are this member" verdict, so every one must
# require a CONFIRMED auth account. ``auth_member_gym_id.sql`` is deliberately
# NOT here: it only maps a member to a gym, and the gym-scoped check that
# follows it carries the predicate.
IDENTITY_SQL_FILES = (
    "auth_resolve_employee.sql",
    "auth_staff_principal.sql",
    "auth_verified_account.sql",
    "auth_member_self.sql",
)

# The caller's ``auth.users`` id (the JWT ``sub``). Every real ``Auth`` call
# below carries it so ``require_sub`` passes and the query binds it as
# ``caller_id``. A fixed uuid so the exact-param assertions can pin it.
_CALLER_ID = "00000000-0000-0000-0000-000000000abc"


def _db_pool(row: object) -> tuple[MagicMock, MagicMock]:
    """A ``DirectDatabasePool`` double whose one query resolves to ``row``.

    Returns ``(db_pool, session)`` so a test can inspect ``session.execute``'s
    SQL text and bind params.
    """
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    session = MagicMock()
    session.execute = AsyncMock(return_value=result)
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=False)
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=cm)
    return db_pool, session


def _params(session: MagicMock) -> dict:
    """The bind params of the (single) query the check issued."""
    return session.execute.call_args.args[1]


def _sql(session: MagicMock) -> str:
    """The SQL text of the (single) query the check issued."""
    return str(session.execute.call_args.args[0])


# ── verify_roles ──────────────────────────────────────────────────


async def test_verify_roles_returns_matched_role_and_binds_params() -> None:
    """A matching row returns its ``employee_type``; the query binds the
    LOWERCASED email, the gym id, and the allowed roles as an array."""
    gym_id = uuid4()
    db_pool, session = _db_pool(
        {"employee_id": str(uuid4()), "employee_type": "front_desk"}
    )
    auth = Auth(db_pool)

    result = await auth.verify_roles(
        gym_id, {"email": "Owner@Test.com", "sub": _CALLER_ID}, STAFF
    )

    assert result is EmployeeType.front_desk
    params = _params(session)
    assert params["gym_id"] == str(gym_id)
    # Email is lowercased BEFORE the query.
    assert params["email"] == "owner@test.com"
    assert set(params["allowed_roles"]) == {r.value for r in STAFF}
    # The caller's own account id (JWT sub) is bound so the query pins the
    # confirmed-account EXISTS to the CALLER, not just some holder of the email.
    assert params["caller_id"] == _CALLER_ID
    assert "email_confirmed_at IS NOT NULL" in _sql(session)


async def test_verify_roles_403_when_no_matching_row() -> None:
    """No matching non-archived, verified row → 403."""
    db_pool, _ = _db_pool(None)
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_roles(
            uuid4(), {"email": "a@b.com", "sub": _CALLER_ID}, OWNER_ADMIN
        )
    assert exc.value.status_code == 403


async def test_verify_roles_401_when_no_email_and_no_query() -> None:
    """A payload with no ``email`` claim is a 401, before any DB query."""
    db_pool, _ = _db_pool(
        {"employee_id": str(uuid4()), "employee_type": "owner"}
    )
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_roles(uuid4(), {}, OWNER_ADMIN)
    assert exc.value.status_code == 401
    db_pool.session.assert_not_called()


async def test_get_employee_id_returns_the_matched_row_id() -> None:
    """``get_employee_id`` returns the resolved row's employee_id."""
    employee_id = uuid4()
    db_pool, _ = _db_pool(
        {"employee_id": str(employee_id), "employee_type": "admin"}
    )
    auth = Auth(db_pool)

    assert (
        await auth.get_employee_id(
            uuid4(), {"email": "a@b.com", "sub": _CALLER_ID}, OWNER_ADMIN
        )
        == employee_id
    )


# ── verify_staff_principal ────────────────────────────────────────


async def test_verify_staff_principal_passes_for_front_desk() -> None:
    """A front_desk row (in ``STAFF``) at any gym passes the gym-agnostic
    staff gate; the query binds the allowed roles and no gym."""
    db_pool, session = _db_pool({"employee_id": str(uuid4())})
    auth = Auth(db_pool)

    result = await auth.verify_staff_principal(
        {"email": "FD@test.com", "sub": _CALLER_ID}, STAFF
    )

    assert result is None
    params = _params(session)
    assert params["email"] == "fd@test.com"
    assert "gym_id" not in params
    assert set(params["allowed_roles"]) == {r.value for r in STAFF}
    assert params["caller_id"] == _CALLER_ID
    assert "email_confirmed_at IS NOT NULL" in _sql(session)


async def test_verify_staff_principal_403_when_none() -> None:
    """No verified staff row anywhere → 403."""
    db_pool, _ = _db_pool(None)
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_staff_principal(
            {"email": "nobody@test.com", "sub": _CALLER_ID}, STAFF
        )
    assert exc.value.status_code == 403


# ── verify_verified_account ───────────────────────────────────────


async def test_verified_account_returns_lowercased_email() -> None:
    """A confirmed auth account returns the caller's lowercased email."""
    db_pool, session = _db_pool({"account_verified": True})
    auth = Auth(db_pool)

    assert (
        await auth.verify_verified_account(
            {"email": "New@Owner.com", "sub": _CALLER_ID}
        )
        == "new@owner.com"
    )
    params = _params(session)
    assert params["email"] == "new@owner.com"
    assert params["caller_id"] == _CALLER_ID


async def test_verified_account_403_when_unconfirmed() -> None:
    """A signup that never confirmed its inbox is a 403, not a pass."""
    db_pool, _ = _db_pool({"account_verified": False})
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_verified_account(
            {"email": "ghost@test.com", "sub": _CALLER_ID}
        )
    assert exc.value.status_code == 403


async def test_verified_account_401_without_email_claim() -> None:
    """No email claim → 401, before any query."""
    db_pool, _ = _db_pool({"account_verified": True})
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_verified_account({})
    assert exc.value.status_code == 401
    db_pool.session.assert_not_called()


async def test_401_when_sub_absent_but_email_present() -> None:
    """A payload with an email but NO ``sub`` claim is a 401, before any query.

    Every identity query pins its confirmed-account ``EXISTS`` to the caller's
    own ``auth.users`` id (the JWT ``sub``), so ``require_sub`` rejects a token
    that carries no ``sub`` — even one with a valid email. Exercised through
    ``verify_verified_account`` (the shortest path over ``require_sub``); email
    is checked first, so the failure here is the missing ``sub``, not email."""
    db_pool, _ = _db_pool({"account_verified": True})
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_verified_account({"email": "someone@test.com"})
    assert exc.value.status_code == 401
    db_pool.session.assert_not_called()


# ── verify_member_self ────────────────────────────────────────────


async def test_member_self_passes_for_the_member() -> None:
    """Email match + verified account + matching gym → allowed."""
    gym_id = uuid4()
    member_id = uuid4()
    db_pool, session = _db_pool(
        {
            "gym_id": str(gym_id),
            "email_matches": True,
            "account_verified": True,
        }
    )
    auth = Auth(db_pool)

    await auth.verify_member_self(
        member_id,
        {"email": "Member@Test.com", "sub": _CALLER_ID},
        gym_id=gym_id,
    )

    params = _params(session)
    assert params == {
        "member_id": str(member_id),
        "email": "member@test.com",
        "caller_id": _CALLER_ID,
    }


async def test_member_self_passes_for_a_parent_on_a_child_row() -> None:
    """The family case: the caller's email is carried on a DIFFERENT member's
    (their child's) row, so the row's email still matches."""
    db_pool, _ = _db_pool(
        {
            "gym_id": str(uuid4()),
            "email_matches": True,
            "account_verified": True,
        }
    )
    auth = Auth(db_pool)

    await auth.verify_member_self(
        uuid4(), {"email": "parent@test.com", "sub": _CALLER_ID}
    )


async def test_member_self_403_when_account_unverified() -> None:
    """Right email, unconfirmed auth account → 403."""
    db_pool, _ = _db_pool(
        {
            "gym_id": str(uuid4()),
            "email_matches": True,
            "account_verified": False,
        }
    )
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_member_self(
            uuid4(), {"email": "member@test.com", "sub": _CALLER_ID}
        )
    assert exc.value.status_code == 403


async def test_member_self_403_when_email_does_not_match() -> None:
    """Someone else's member row → 403."""
    db_pool, _ = _db_pool(
        {
            "gym_id": str(uuid4()),
            "email_matches": False,
            "account_verified": True,
        }
    )
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_member_self(
            uuid4(), {"email": "other@test.com", "sub": _CALLER_ID}
        )
    assert exc.value.status_code == 403


async def test_member_self_403_when_member_is_at_another_gym() -> None:
    """The gym scoping: the same email must not reach a same-named member at
    an unrelated gym."""
    db_pool, _ = _db_pool(
        {
            "gym_id": str(uuid4()),
            "email_matches": True,
            "account_verified": True,
        }
    )
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_member_self(
            uuid4(),
            {"email": "member@test.com", "sub": _CALLER_ID},
            gym_id=uuid4(),
        )
    assert exc.value.status_code == 403


async def test_member_self_404_when_member_missing() -> None:
    """A missing member row is a 404, not a 403."""
    db_pool, _ = _db_pool(None)
    auth = Auth(db_pool)

    with pytest.raises(HTTPException) as exc:
        await auth.verify_member_self(
            uuid4(), {"email": "x@y.com", "sub": _CALLER_ID}
        )
    assert exc.value.status_code == 404


# ── drift guard ───────────────────────────────────────────────────


@pytest.mark.parametrize("sql_file", IDENTITY_SQL_FILES)
def test_identity_sql_requires_a_confirmed_account(sql_file: str) -> None:
    """Every identity-resolving query must require a CONFIRMED auth account.

    Read off disk on purpose: this is the one predicate stopping anyone from
    signing up as ``owner@somegym.com`` and being handed that gym. Dropping it
    would leave every unit test above green (they mock the DB), so the guard
    reads the real SQL. It also pins the scalar ``EXISTS`` — ``auth.users`` is
    unique on email only ``WHERE is_sso_user = false``, so a JOIN can fan out.
    """
    sql = (Path(SQL_DIR) / sql_file).read_text()
    assert "email_confirmed_at IS NOT NULL" in sql
    assert "EXISTS (" in sql
    assert "JOIN auth.users" not in sql
    # The confirmed-account EXISTS must be pinned to the CALLER's own account
    # (the JWT sub), not merely to some confirmed holder of the email — so an
    # unconfirmed signup on an address a different (e.g. SSO) confirmed row also
    # holds cannot borrow that row's verification.
    assert "u.id = CAST(:caller_id AS UUID)" in sql
