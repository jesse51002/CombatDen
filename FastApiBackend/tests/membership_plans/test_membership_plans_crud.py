"""Integration tests for MembershipPlansService (lighter coverage)."""

from src.membership_plans.membership_plans_schemas import (
    MembershipPlanCreateRequest,
    MembershipPlanPriceRequest,
    MembershipPlanUpdateData,
    MembershipPlanUpdateRequest,
)

from schema.membership_plan import DurationUnit, PlanType


async def test_create_recurring_plan(plans_service, gym_id):
    resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Monthly Recurring",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=5000,
        ),
    )

    assert resp.plan_id is not None
    assert resp.plan_name == "Monthly Recurring"
    assert resp.plan_type == PlanType.recurring
    assert resp.stripe_product_id is not None
    assert resp.active_price is not None
    assert resp.active_price.price == 5000
    assert resp.active_price.stripe_price_id is not None


async def test_create_one_time_plan(plans_service, gym_id):
    resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Drop-In",
            plan_type=PlanType.one_time,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=2000,
        ),
    )

    assert resp.plan_type == PlanType.one_time
    assert resp.active_price.price == 2000


async def test_update_plan_name(plans_service, gym_id):
    created = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Before Update",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=4000,
        ),
    )

    resp = await plans_service.update_plan(
        MembershipPlanUpdateRequest(
            plan_id=created.plan_id,
            gym_id=gym_id,
            data=MembershipPlanUpdateData(plan_name="After Update"),
        ),
    )

    assert resp.plan_name == "After Update"


async def test_delete_plan(plans_service, gym_id):
    created = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Delete Me",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=3000,
        ),
    )

    await plans_service.delete_plan(created.plan_id, gym_id)

    # Plan should not appear in the list anymore
    plans = await plans_service.list_plans(gym_id)
    plan_ids = {p.plan_id for p in plans}
    assert created.plan_id not in plan_ids


async def test_list_plans(plans_service, gym_id):
    await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="List Test A",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=1000,
        ),
    )
    await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="List Test B",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=2000,
        ),
    )

    plans = await plans_service.list_plans(gym_id)
    names = {p.plan_name for p in plans}

    assert "List Test A" in names
    assert "List Test B" in names


async def test_set_price(plans_service, gym_id):
    created = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Price Change",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=5000,
        ),
    )
    old_price_id = created.active_price.price_id

    resp = await plans_service.set_price(
        MembershipPlanPriceRequest(
            plan_id=created.plan_id,
            gym_id=gym_id,
            price=7500,
        ),
    )

    assert resp.price == 7500
    assert resp.is_active is True
    assert resp.price_id != old_price_id
