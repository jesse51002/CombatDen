"""Integration tests for MembershipPlansService.

Each success path fetches the Stripe product and price it produced
and asserts the resources exist with the expected state (active,
amount, etc.). No customer/invoice checks here — plans don't bill
members, they only configure what gets billed when a membership
starts.
"""

from schema.membership_plan import DurationUnit, PlanType

from src.membership_plans.membership_plans_schemas import (
    MembershipPlanCreateRequest,
    MembershipPlanPriceRequest,
    MembershipPlanUpdateData,
    MembershipPlanUpdateRequest,
)


async def _fetch_product(stripe_client, product_id, connect_opts):
    return await stripe_client.client.v1.products.retrieve_async(
        product_id,
        options=connect_opts,
    )


async def _fetch_price(stripe_client, price_id, connect_opts):
    return await stripe_client.client.v1.prices.retrieve_async(
        price_id,
        options=connect_opts,
    )


async def test_create_recurring_plan(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
):
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

    # Stripe side: product + price must exist and match.
    product = await _fetch_product(
        stripe_client,
        resp.stripe_product_id,
        connect_opts,
    )
    assert product.active is True
    assert product.name == "Monthly Recurring"

    price = await _fetch_price(
        stripe_client,
        resp.active_price.stripe_price_id,
        connect_opts,
    )
    assert price.active is True
    assert price.unit_amount == 5000
    assert price.recurring is not None, (
        f"Recurring plan Stripe price {price.id} is missing its recurring block"
    )
    assert price.recurring.interval == "month"


async def test_create_one_time_plan(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
):
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

    # One-time prices have no ``recurring`` block on Stripe.
    price = await _fetch_price(
        stripe_client,
        resp.active_price.stripe_price_id,
        connect_opts,
    )
    assert price.active is True
    assert price.unit_amount == 2000
    assert price.recurring is None, (
        f"One-time Stripe price {price.id} unexpectedly has a recurring block"
    )


async def test_update_plan_name(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
):
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

    # Stripe product name must be in sync with the CRM plan name.
    product = await _fetch_product(
        stripe_client,
        created.stripe_product_id,
        connect_opts,
    )
    assert product.name == "After Update", (
        f"Stripe product {product.id} name={product.name!r} not updated"
    )
    assert product.active is True


async def test_delete_plan(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
):
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

    await plans_service.delete_plan(
        created.plan_id,
        gym_id,
    )

    # Plan should not appear in the list anymore
    plans = await plans_service.list_plans(gym_id)
    plan_ids = {p.plan_id for p in plans}
    assert created.plan_id not in plan_ids

    # Stripe side: deleting a plan soft-archives the underlying
    # product (Stripe does not allow hard-deleting products that
    # have ever been used on a subscription).
    product = await _fetch_product(
        stripe_client,
        created.stripe_product_id,
        connect_opts,
    )
    assert product.active is False, f"Stripe product {product.id} still active after plan delete"


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


async def test_set_price(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
):
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
    old_stripe_price_id = created.active_price.stripe_price_id

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

    # Stripe side: a brand-new active price must exist at the new
    # amount.
    new_price = await _fetch_price(
        stripe_client,
        resp.stripe_price_id,
        connect_opts,
    )
    assert new_price.active is True
    assert new_price.unit_amount == 7500

    # Old Stripe price must be archived after the swap. The service
    # points ``product.default_price`` at the new price first (Stripe
    # refuses to archive the current default), then calls
    # ``deactivate_price`` on the old one.
    old_price = await _fetch_price(
        stripe_client,
        old_stripe_price_id,
        connect_opts,
    )
    assert old_price.active is False, (
        f"Old Stripe price {old_price.id} should be archived after set_price"
    )
