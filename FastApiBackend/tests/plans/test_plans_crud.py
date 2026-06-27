"""Integration tests for MembershipPlansService.

Each success path fetches the Stripe product and price it produced
and asserts the resources exist with the expected state (active,
amount, etc.). No customer/invoice checks here — plans don't bill
members, they only configure what gets billed when a membership
starts.
"""

from uuid import uuid4

from schema.membership_plan import DurationUnit, PlanType

from src.plans.plans_schema import (
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


def _track_plan(created, resp):
    """Register a created plan + its Stripe product/price for teardown."""
    created.track_plan_db(resp.plan_id)
    created.track_product(resp.stripe_product_id)
    created.track_price(resp.active_price.stripe_price_id)


async def test_create_recurring_plan(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
    created,
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
    _track_plan(created, resp)

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
    created,
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
    _track_plan(created, resp)

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
    created,
):
    created_resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Before Update",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=4000,
        ),
    )
    _track_plan(created, created_resp)

    resp = await plans_service.update_plan(
        MembershipPlanUpdateRequest(
            plan_id=created_resp.plan_id,
            gym_id=gym_id,
            data=MembershipPlanUpdateData(plan_name="After Update"),
        ),
    )

    assert resp.plan_name == "After Update"

    # Stripe product name must be in sync with the CRM plan name.
    product = await _fetch_product(
        stripe_client,
        created_resp.stripe_product_id,
        connect_opts,
    )
    assert product.name == "After Update", (
        f"Stripe product {product.id} name={product.name!r} not updated"
    )
    assert product.active is True


async def test_update_plan_with_waiver_ids(
    plans_service,
    gym_id,
    created,
):
    """Updating a plan whose changes include a jsonb column must not 500.

    Regression for the dynamic SET-clause builder emitting
    ``waiver_ids = :waiver_ids::jsonb`` — asyncpg cannot bind a param
    immediately followed by ``::``, so Postgres raised
    ``syntax error at or near ":"``. The builder must use
    ``CAST(:waiver_ids AS JSONB)`` (see CLAUDE.md → SQL Files). The plain
    name-only update never exercised this branch, which is how the bug shipped.
    """
    created_resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Waiver Update",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=4500,
        ),
    )
    _track_plan(created, created_resp)

    waiver_id = uuid4()  # jsonb array element; no FK, any uuid is valid
    resp = await plans_service.update_plan(
        MembershipPlanUpdateRequest(
            plan_id=created_resp.plan_id,
            gym_id=gym_id,
            data=MembershipPlanUpdateData(
                plan_name="Waiver Update",
                duration_amount=1,
                duration_unit=DurationUnit.month,
                waiver_ids=[waiver_id],
            ),
        ),
    )

    # The jsonb column round-trips through the CAST(...) SET clause.
    assert resp.waiver_ids == [waiver_id]


async def test_delete_plan(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    created_resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Delete Me",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=3000,
        ),
    )
    _track_plan(created, created_resp)

    await plans_service.delete_plan(
        created_resp.plan_id,
        gym_id,
    )

    # Plan should not appear in the list anymore
    plans = await plans_service.list_plans(gym_id)
    plan_ids = {p.plan_id for p in plans}
    assert created_resp.plan_id not in plan_ids

    # Stripe side: deleting a plan soft-archives the underlying
    # product (Stripe does not allow hard-deleting products that
    # have ever been used on a subscription).
    product = await _fetch_product(
        stripe_client,
        created_resp.stripe_product_id,
        connect_opts,
    )
    assert product.active is False, f"Stripe product {product.id} still active after plan delete"


async def test_list_plans(plans_service, gym_id, created):
    plan_a = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="List Test A",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=1000,
        ),
    )
    _track_plan(created, plan_a)
    plan_b = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="List Test B",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=2000,
        ),
    )
    _track_plan(created, plan_b)

    plans = await plans_service.list_plans(gym_id)
    names = {p.plan_name for p in plans}

    assert "List Test A" in names
    assert "List Test B" in names


async def test_set_price(
    plans_service,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    created_resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Price Change",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=5000,
        ),
    )
    _track_plan(created, created_resp)
    old_price_id = created_resp.active_price.price_id
    old_stripe_price_id = created_resp.active_price.stripe_price_id

    resp = await plans_service.set_price(
        MembershipPlanPriceRequest(
            plan_id=created_resp.plan_id,
            gym_id=gym_id,
            price=7500,
        ),
    )
    # set_price mints a new active Stripe price; archive it on teardown too.
    created.track_price(resp.stripe_price_id)

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

    # The old Stripe price stays ACTIVE after the swap — set_price never
    # archives a Stripe price (the DB ``is_active`` flag is the single gate for
    # which price is current; archiving the old price would break an in-flight
    # subscription migration onto the new one). The service only re-points
    # ``product.default_price`` at the new price.
    old_price = await _fetch_price(
        stripe_client,
        old_stripe_price_id,
        connect_opts,
    )
    assert old_price.active is True, (
        f"Old Stripe price {old_price.id} should stay active after set_price "
        f"(set_price never archives a Stripe price)"
    )


async def test_list_prices(plans_service, gym_id, created):
    """list_prices returns every version, active first, with member counts."""
    created_resp = await plans_service.create_plan(
        MembershipPlanCreateRequest(
            gym_id=gym_id,
            plan_name="Versioned Price",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit=DurationUnit.month,
            price=6000,
        ),
    )
    _track_plan(created, created_resp)
    old_price_id = created_resp.active_price.price_id

    new_price = await plans_service.set_price(
        MembershipPlanPriceRequest(
            plan_id=created_resp.plan_id,
            gym_id=gym_id,
            price=8000,
        ),
    )
    created.track_price(new_price.stripe_price_id)

    prices = await plans_service.list_prices(created_resp.plan_id, gym_id)

    # Both versions present; active (new) first.
    assert len(prices) == 2
    assert prices[0].is_active is True
    assert prices[0].price == 8000
    assert prices[1].is_active is False
    assert prices[1].price_id == old_price_id
    # No memberships were started, so every version has 0 members.
    assert all(p.member_count == 0 for p in prices)
