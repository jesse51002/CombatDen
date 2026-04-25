"""Integration tests for link_account pre-flight check."""

from uuid import uuid4

import pytest

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)

# ── Happy path ──────────────────────────────────────────────────


async def test_check_happy_path(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    parent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Parent",
        last_name="Check",
    )
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Child",
        last_name="Check",
    )

    try:
        result = await management_service.check_link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )
        assert result.can_link is True
        assert result.error is None
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


# ── Blocking rules ──────────────────────────────────────────────


async def test_check_self_link_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
    )

    try:
        result = await management_service.check_link_account(
            member.crm_user_id,
            member.crm_user_id,
        )
        assert result.can_link is False
        assert "different payer" in result.error
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_check_already_linked_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    parent1 = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="P1",
        last_name="AL",
    )
    parent2 = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="P2",
        last_name="AL",
    )
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="C",
        last_name="AL",
    )

    try:
        await management_service.link_account(
            child.crm_user_id,
            parent1.crm_user_id,
        )

        result = await management_service.check_link_account(
            child.crm_user_id,
            parent2.crm_user_id,
        )
        assert result.can_link is False
        assert "already linked" in result.error
        assert "Unlink them first" in result.error
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent1.crm_user_id)
        await delete_member_data(db_pool, parent2.crm_user_id)


async def test_check_candidate_is_parent_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """A candidate that already has linked children cannot become a child."""
    grandparent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="GP",
        last_name="IsParent",
    )
    candidate = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Cand",
        last_name="IsParent",
    )
    # A child linked to `candidate` — making `candidate` a parent.
    child_req = MembersManagementCreateRequest(
        gym_id=gym_id,
        first_name="Kid",
        last_name="IsParent",
        account_linked_to_id=candidate.crm_user_id,
    )
    kid = await management_service.create_member(child_req)

    try:
        result = await management_service.check_link_account(
            candidate.crm_user_id,
            grandparent.crm_user_id,
        )
        assert result.can_link is False
        assert "already has other members linked" in result.error
    finally:
        await delete_member_data(db_pool, kid.crm_user_id)
        await delete_member_data(db_pool, candidate.crm_user_id)
        await delete_member_data(db_pool, grandparent.crm_user_id)


async def test_check_parent_is_child_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """The selected payer cannot itself be linked to another account."""
    top_parent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Top",
        last_name="PC",
    )
    middle = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Mid",
        last_name="PC",
    )
    candidate = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Cand",
        last_name="PC",
    )

    try:
        # Make `middle` a child of `top_parent`.
        await management_service.link_account(
            middle.crm_user_id,
            top_parent.crm_user_id,
        )

        result = await management_service.check_link_account(
            candidate.crm_user_id,
            middle.crm_user_id,
        )
        assert result.can_link is False
        assert "top-level paying account" in result.error
    finally:
        await delete_member_data(db_pool, middle.crm_user_id)
        await delete_member_data(db_pool, candidate.crm_user_id)
        await delete_member_data(db_pool, top_parent.crm_user_id)


async def test_check_active_recurring_blocked(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    parent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="P",
        last_name="RecCheck",
    )
    pm_id = await create_payment_method(stripe_client, connect_opts)
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="C",
        last_name="RecCheck",
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        await memberships_service.start(
            crm_user_id=child.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        result = await management_service.check_link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )
        assert result.can_link is False
        assert "active recurring" in result.error
        assert "Cancel all recurring memberships" in result.error
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


async def test_check_parent_not_found_blocked(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    child = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="C",
        last_name="NoPayer",
    )

    try:
        result = await management_service.check_link_account(
            child.crm_user_id,
            uuid4(),
        )
        assert result.can_link is False
        assert "could not be found" in result.error
    finally:
        await delete_member_data(db_pool, child.crm_user_id)


async def test_check_candidate_not_found_raises(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    parent = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="P",
        last_name="NoChild",
    )

    try:
        with pytest.raises(ValueError, match="not found"):
            await management_service.check_link_account(
                uuid4(),
                parent.crm_user_id,
            )
    finally:
        await delete_member_data(db_pool, parent.crm_user_id)
