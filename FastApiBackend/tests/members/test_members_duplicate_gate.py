"""Tests for the duplicate-member gate on member creation.

Unit tests cover the schema default and the ``_check_duplicate`` gate logic in
isolation (no DB / Stripe). Integration tests drive the real
``MembersManagementService.create_member`` against the shared DB + Stripe test
account: a same-identity create is rejected with 409 and nothing is written,
``allow_duplicate=true`` then creates anyway, and a null-email create is never
gated.
"""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import text

from src.members.schema.members_schema import MemberCreateRequest
from src.members.service.management.members_management_create import (
    MembersManagementCreate,
)

# ── Unit: schema default ────────────────────────────────────────


def test_allow_duplicate_defaults_false():
    request = MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        email="ada@example.com",
        send_invite=False,
    )
    assert request.allow_duplicate is False


# ── Unit: _check_duplicate gate logic (stubbed lookup) ──────────


async def test_check_duplicate_noop_when_email_none():
    """A null-email request never runs the lookup and never raises."""
    svc = MembersManagementCreate(None, None)
    svc._find_duplicates = AsyncMock(side_effect=AssertionError("should not run"))

    request = MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        email=None,
        send_invite=False,
    )
    await svc._check_duplicate(request)  # no raise
    svc._find_duplicates.assert_not_awaited()


async def test_check_duplicate_noop_when_allow_duplicate():
    """An explicit allow_duplicate=True skips the lookup entirely."""
    svc = MembersManagementCreate(None, None)
    svc._find_duplicates = AsyncMock(side_effect=AssertionError("should not run"))

    request = MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        email="ada@example.com",
        allow_duplicate=True,
        send_invite=False,
    )
    await svc._check_duplicate(request)  # no raise
    svc._find_duplicates.assert_not_awaited()


async def test_check_duplicate_passes_when_no_match():
    svc = MembersManagementCreate(None, None)
    svc._find_duplicates = AsyncMock(return_value=[])

    request = MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        email="ada@example.com",
        send_invite=False,
    )
    await svc._check_duplicate(request)  # no raise
    svc._find_duplicates.assert_awaited_once()


async def test_check_duplicate_raises_409_with_matches():
    match = {
        "member_id": str(uuid4()),
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
        "photo_url": None,
    }
    svc = MembersManagementCreate(None, None)
    svc._find_duplicates = AsyncMock(return_value=[match])

    request = MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        email="ada@example.com",
        send_invite=False,
    )
    with pytest.raises(HTTPException) as exc_info:
        await svc._check_duplicate(request)

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == {
        "code": "duplicate_member",
        "matches": [match],
    }


# ── Integration: real service, DB + Stripe ──────────────────────


async def _count_members_by_email(db_pool, gym_id, email) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT count(*) AS n FROM members "
                "WHERE gym_id = :gym_id AND lower(email) = lower(:email)"
            ),
            {"gym_id": str(gym_id), "email": email},
        )
        return result.mappings().one()["n"]


async def test_duplicate_gate_409_then_allow_duplicate(
    management_service,
    db_pool,
    gym_id,
    created,
):
    email = f"dupgate-{uuid4()}@example.com"

    first = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="DupGate",
            last_name="Tester",
            email=email,
            send_invite=False,
        ),
    ).member
    created.track_member(first.member_id)
    created.track_customer(first.stripe_customer_id)

    # A same-identity create (same gym + name + email) is rejected with 409
    # carrying the candidate rows, and nothing new is written.
    with pytest.raises(HTTPException) as exc_info:
        await management_service.create_member(
            MemberCreateRequest(
                gym_id=gym_id,
                first_name="DupGate",
                last_name="Tester",
                email=email,
                send_invite=False,
            ),
        ).member
    assert exc_info.value.status_code == 409
    detail = exc_info.value.detail
    assert detail["code"] == "duplicate_member"
    match_ids = {m["member_id"] for m in detail["matches"]}
    assert str(first.member_id) in match_ids

    assert await _count_members_by_email(db_pool, gym_id, email) == 1

    # Re-sending with allow_duplicate=true creates the member anyway.
    second = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="DupGate",
            last_name="Tester",
            email=email,
            allow_duplicate=True,
            send_invite=False,
        ),
    ).member
    created.track_member(second.member_id)
    created.track_customer(second.stripe_customer_id)

    assert second.member_id != first.member_id
    assert await _count_members_by_email(db_pool, gym_id, email) == 2


async def test_duplicate_gate_normalizes_case_and_whitespace(
    management_service,
    gym_id,
    created,
):
    """A case- and whitespace-varied identity still trips the 409 gate.

    ``find_members_by_identity.sql`` matches on
    ``lower(trim(first_name / last_name / email))``, so a second create with the
    same identity in different case + surrounding whitespace (and a case-varied
    email) is rejected as a duplicate. ``lower()`` of an uppercased hex suffix
    returns the original suffix, so reusing it across both creates is safe.
    EmailStr strips surrounding whitespace and lowercases only the domain
    (preserving local-part case), so the email variant is CASE-only — padding
    would be normalized away before the gate ever saw it, but an uppercased
    local part reaches the DB and genuinely exercises the SQL ``lower(email)``.
    """
    suffix = uuid4().hex[:8]

    first = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name=f"Ada{suffix}",
            last_name="Lovelace",
            email=f"ada.{suffix}@example.com",
            send_invite=False,
        ),
    ).member
    created.track_member(first.member_id)
    created.track_customer(first.stripe_customer_id)

    # Same identity, mixed case + surrounding whitespace on the names and a
    # case-varied email — the normalized gate must still reject it (nothing
    # new is written, so only ``first`` needs cleanup).
    with pytest.raises(HTTPException) as exc_info:
        await management_service.create_member(
            MemberCreateRequest(
                gym_id=gym_id,
                first_name=f"  ADA{suffix.upper()}  ",
                last_name="  lovelace ",
                email=f"ADA.{suffix.upper()}@EXAMPLE.COM",
                send_invite=False,
            ),
        )

    assert exc_info.value.status_code == 409
    detail = exc_info.value.detail
    assert detail["code"] == "duplicate_member"
    match_ids = {m["member_id"] for m in detail["matches"]}
    assert str(first.member_id) in match_ids


async def test_null_email_create_never_gated(
    management_service,
    gym_id,
    created,
):
    """A null-email member is never gated, even against a same-name member."""
    name_suffix = uuid4().hex[:8]
    last_name = f"NullEmail{name_suffix}"

    first = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Casey",
            last_name=last_name,
            email=None,
            send_invite=False,
        ),
    ).member
    created.track_member(first.member_id)
    created.track_customer(first.stripe_customer_id)

    # Same name, still no email — the gate never runs, so this succeeds.
    second = await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Casey",
            last_name=last_name,
            email=None,
            send_invite=False,
        ),
    ).member
    created.track_member(second.member_id)
    created.track_customer(second.stripe_customer_id)

    assert second.member_id != first.member_id
