"""Integration tests for link_account pre-flight check."""

from uuid import uuid4

import pytest

from src.members.schema.members_schema import MemberCreateRequest
from tests.helpers.cleanup import delete_member_data

# ── Happy path ──────────────────────────────────────────────────


async def test_check_happy_path(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="Parent", last_name="Check")
    child = await created.member(gym_id, first_name="Child", last_name="Check")

    try:
        result = await management_service.check_link_account(
            child.member_id,
            parent.member_id,
        )
        assert result.can_link is True
        assert result.error is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Blocking rules ──────────────────────────────────────────────


async def test_check_self_link_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = await created.member(gym_id)

    try:
        result = await management_service.check_link_account(
            member.member_id,
            member.member_id,
        )
        assert result.can_link is False
        assert "different payer" in result.error
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_check_already_linked_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent1 = await created.member(gym_id, first_name="P1", last_name="AL")
    parent2 = await created.member(gym_id, first_name="P2", last_name="AL")
    child = await created.member(gym_id, first_name="C", last_name="AL")

    try:
        await management_service.link_account(
            child.member_id,
            parent1.member_id,
        )

        result = await management_service.check_link_account(
            child.member_id,
            parent2.member_id,
        )
        assert result.can_link is False
        assert "already linked" in result.error
        assert "Unlink them first" in result.error
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent1.member_id)
        await delete_member_data(db_pool, parent2.member_id)


async def test_check_candidate_is_parent_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A candidate that already has linked children cannot become a child."""
    grandparent = await created.member(gym_id, first_name="GP", last_name="IsParent")
    candidate = await created.member(gym_id, first_name="Cand", last_name="IsParent")
    kid_req = MemberCreateRequest(
        gym_id=gym_id,
        first_name="Kid",
        last_name="IsParent",
    )
    kid = await management_service.create_member(kid_req)
    created.track_customer(kid.stripe_customer_id)

    try:
        # Link kid to candidate via the supported flow — this makes candidate a
        # parent (create_member never sets account_linked_to_id).
        await management_service.link_account(kid.member_id, candidate.member_id)
        result = await management_service.check_link_account(
            candidate.member_id,
            grandparent.member_id,
        )
        assert result.can_link is False
        assert "already has other members linked" in result.error
    finally:
        await delete_member_data(db_pool, kid.member_id)
        await delete_member_data(db_pool, candidate.member_id)
        await delete_member_data(db_pool, grandparent.member_id)


async def test_check_parent_is_child_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """The selected payer cannot itself be linked to another account."""
    top_parent = await created.member(gym_id, first_name="Top", last_name="PC")
    middle = await created.member(gym_id, first_name="Mid", last_name="PC")
    candidate = await created.member(gym_id, first_name="Cand", last_name="PC")

    try:
        # Make `middle` a child of `top_parent`.
        await management_service.link_account(
            middle.member_id,
            top_parent.member_id,
        )

        result = await management_service.check_link_account(
            candidate.member_id,
            middle.member_id,
        )
        assert result.can_link is False
        assert "top-level paying account" in result.error
    finally:
        await delete_member_data(db_pool, middle.member_id)
        await delete_member_data(db_pool, candidate.member_id)
        await delete_member_data(db_pool, top_parent.member_id)


async def test_check_active_recurring_blocked(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="RecCheck")
    pm_id = await created.payment_method()
    child = await created.member(
        gym_id,
        first_name="C",
        last_name="RecCheck",
        payment_method_id=pm_id,
    )
    plan = await created.plan(gym_id)

    try:
        await memberships_service.start(
            member_id=child.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        result = await management_service.check_link_account(
            child.member_id,
            parent.member_id,
        )
        assert result.can_link is False
        assert "active recurring" in result.error
        assert "Cancel all recurring memberships" in result.error
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_check_parent_not_found_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    child = await created.member(gym_id, first_name="C", last_name="NoPayer")

    try:
        result = await management_service.check_link_account(
            child.member_id,
            uuid4(),
        )
        assert result.can_link is False
        assert "could not be found" in result.error
    finally:
        await delete_member_data(db_pool, child.member_id)


async def test_check_candidate_not_found_raises(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="NoChild")

    try:
        with pytest.raises(ValueError, match="not found"):
            await management_service.check_link_account(
                uuid4(),
                parent.member_id,
            )
    finally:
        await delete_member_data(db_pool, parent.member_id)
