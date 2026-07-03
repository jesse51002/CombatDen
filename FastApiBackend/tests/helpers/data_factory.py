"""Test data factory — create members, plans, prices, discounts.

Each function follows the production DB-first pattern:
INSERT with NULL stripe ID -> Stripe API -> UPDATE stripe ID.

Standalone module — no pytest imports, no fixture dependencies.
Every function accepts its dependencies as explicit parameters.
"""
from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

import stripe
from sqlalchemy import text

from src.core.config import settings
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.database import DirectDatabasePool

# ── Return types ────────────────────────────────────────────────


@dataclass(frozen=True)
class TestMember:
    member_id: UUID
    stripe_customer_id: str
    payment_method_id: str | None


@dataclass(frozen=True)
class TestPlan:
    plan_id: UUID
    price_id: UUID
    stripe_product_id: str
    stripe_price_id: str
    plan_type: str
    price_cents: int


@dataclass(frozen=True)
class TestDiscount:
    discount_id: UUID
    value_id: UUID


@dataclass(frozen=True)
class TestReward:
    reward_id: UUID
    gym_id: UUID


# ── Payment method ──────────────────────────────────────────────


async def create_payment_method(
    stripe_client: PaymentsStripeClient,
    connect_opts: stripe.RequestOptions,
) -> str:
    """Create a test Visa payment method on a connected account.

    Returns:
        The payment method ID (``pm_...``).
    """
    pm = await stripe_client.client.v1.payment_methods.create_async(
        params={"type": "card", "card": {"token": "tok_visa"}},
        options=connect_opts,
    )
    return pm.id


# ── Member ──────────────────────────────────────────────────────


async def create_member(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
    gym_id: UUID,
    connect_opts: stripe.RequestOptions,
    *,
    first_name: str = "Test",
    last_name: str = "Member",
    payment_method_id: str | None = None,
    test_clock_id: str | None = None,
) -> TestMember:
    """Create a member profile with a Stripe customer (DB-first).

    1. INSERT into members (stripe_customer_id = NULL)
    2. Create Stripe customer on connected account
    3. UPDATE members row with stripe_customer_id + card details
    """
    # Step 1: Insert member row
    insert_member_sql = """
        INSERT INTO members (
            gym_id, first_name, last_name
        ) VALUES (
            :gym_id, :first_name, :last_name
        )
        RETURNING member_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_member_sql),
            {"gym_id": str(gym_id), "first_name": first_name, "last_name": last_name},
        )
        row = result.mappings().fetchone()
        await session.commit()
    member_id = UUID(str(row["member_id"]))

    # Step 2: Create Stripe customer
    customer_params: dict = {
        "name": f"{first_name} {last_name}",
        "metadata": {"crm_pk": str(member_id)},
    }
    if test_clock_id:
        customer_params["test_clock"] = test_clock_id
    if payment_method_id:
        customer_params["payment_method"] = payment_method_id
        customer_params["invoice_settings"] = {
            "default_payment_method": payment_method_id,
        }

    customer = await stripe_client.client.v1.customers.create_async(
        params=customer_params,
        options=connect_opts,
    )

    # Step 3: Update members row with Stripe IDs
    card_brand = card_last_four = None
    card_exp_month = card_exp_year = None
    stripe_pm_id = None

    if payment_method_id:
        pm = await stripe_client.client.v1.payment_methods.retrieve_async(
            payment_method_id,
            options=connect_opts,
        )
        stripe_pm_id = pm.id
        if pm.card:
            card_brand = pm.card.brand
            card_last_four = pm.card.last4
            card_exp_month = pm.card.exp_month
            card_exp_year = pm.card.exp_year

    update_sql = """
        UPDATE members
        SET stripe_customer_id = :stripe_customer_id,
            stripe_payment_method_id = :stripe_pm_id,
            card_brand = :card_brand,
            card_last_four = :card_last_four,
            card_exp_month = :card_exp_month,
            card_exp_year = :card_exp_year
        WHERE member_id = :member_id
    """
    async with db_pool.session() as session:
        await session.execute(
            text(update_sql),
            {
                "stripe_customer_id": customer.id,
                "stripe_pm_id": stripe_pm_id,
                "card_brand": card_brand,
                "card_last_four": card_last_four,
                "card_exp_month": card_exp_month,
                "card_exp_year": card_exp_year,
                "member_id": str(member_id),
            },
        )
        await session.commit()

    return TestMember(
        member_id=member_id,
        stripe_customer_id=customer.id,
        payment_method_id=payment_method_id,
    )


# ── Membership plan + price ─────────────────────────────────────


async def create_plan(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
    gym_id: UUID,
    connect_opts: stripe.RequestOptions,
    *,
    plan_type: str = "recurring",
    plan_name: str = "Test Plan",
    price_cents: int = 5000,
    duration_amount: int | None = None,
    duration_unit: str | None = None,
) -> TestPlan:
    """Create a membership plan + price (DB-first).

    1. INSERT plan (stripe_product_id = NULL)
    2. Create Stripe product
    3. UPDATE plan with stripe_product_id
    4. Create Stripe price
    5. INSERT price row with stripe_price_id
    """
    # Defaults for plan_type
    if plan_type == "recurring":
        duration_amount = duration_amount or 1
        duration_unit = duration_unit or "month"
    elif plan_type in ("one_time", "trial") and duration_amount is None:
        duration_amount = 1
        duration_unit = duration_unit or "month"

    # Step 1: Insert pending plan row
    insert_plan_sql = """
        INSERT INTO membership_plans_unfiltered (
            gym_id, plan_name, plan_type, duration_amount, duration_unit, is_public
        ) VALUES (
            :gym_id, :plan_name, :plan_type, :duration_amount, :duration_unit, true
        )
        RETURNING plan_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_plan_sql),
            {
                "gym_id": str(gym_id),
                "plan_name": plan_name,
                "plan_type": plan_type,
                "duration_amount": duration_amount,
                "duration_unit": duration_unit,
            },
        )
        plan_row = result.mappings().fetchone()
        await session.commit()
    plan_id = UUID(str(plan_row["plan_id"]))

    # Step 2: Create Stripe product
    product = await stripe_client.client.v1.products.create_async(
        params={
            "name": plan_name,
            "metadata": {"crm_pk": str(plan_id)},
        },
        options=connect_opts,
    )

    # Step 3: Update plan with stripe_product_id
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE membership_plans_unfiltered "
                "SET stripe_product_id = :stripe_product_id "
                "WHERE plan_id = :plan_id"
            ),
            {"stripe_product_id": product.id, "plan_id": str(plan_id)},
        )
        await session.commit()

    # Step 4: Create Stripe price
    price_params: dict = {
        "product": product.id,
        "unit_amount": price_cents,
        "currency": "usd",
    }
    if plan_type == "recurring":
        price_params["recurring"] = {"interval": "month", "interval_count": 1}

    stripe_price = await stripe_client.client.v1.prices.create_async(
        params=price_params,
        options=connect_opts,
    )

    # Step 5: Insert price row
    insert_price_sql = """
        INSERT INTO membership_plan_prices_unfiltered (
            plan_id, gym_id, stripe_price_id, price, is_active
        ) VALUES (
            :plan_id, :gym_id, :stripe_price_id, :price, true
        )
        RETURNING price_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_price_sql),
            {
                "plan_id": str(plan_id),
                "gym_id": str(gym_id),
                "stripe_price_id": stripe_price.id,
                "price": price_cents,
            },
        )
        price_row = result.mappings().fetchone()
        await session.commit()
    price_id = UUID(str(price_row["price_id"]))

    return TestPlan(
        plan_id=plan_id,
        price_id=price_id,
        stripe_product_id=product.id,
        stripe_price_id=stripe_price.id,
        plan_type=plan_type,
        price_cents=price_cents,
    )


# ── Discount ────────────────────────────────────────────────────


async def create_discount(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    *,
    name: str = "Test Discount",
    percentage_off: float | None = 10,
    dollar_off: int | None = None,
    duration_amount: int | None = None,
    duration_unit: str | None = None,
    end_date: str | None = None,
) -> TestDiscount:
    """Create a coupon-free discount preset (identity + first active version).

    Mirrors the production create path (``DiscountsCreate``): two inserts in one
    transaction — the IDENTITY row (``gym_discounts``: name + type) and its first
    ACTIVE value version (``gym_discount_values``: percent/dollar + lifetime).
    No Stripe coupon is pre-baked — the sync computes each consolidated line's
    coupon and writes the resolved id back onto the applied-discount row. The
    lifetime spec is either a duration span (duration_amount + duration_unit) or
    an explicit end_date — never both; neither = forever. Applied-discount rows
    reference the returned ``value_id``.
    """
    discount_type = "preset"

    identity_sql = """
        INSERT INTO gym_discounts_unfiltered (
            gym_id, discount_name, discount_type, is_deleted
        ) VALUES (
            :gym_id, :discount_name, :discount_type, false
        )
        RETURNING discount_id
    """
    value_sql = """
        INSERT INTO gym_discount_values_unfiltered (
            discount_id, gym_id,
            percentage_off, dollar_off,
            duration_amount, duration_unit, end_date,
            is_active
        ) VALUES (
            :discount_id, :gym_id,
            :percentage_off, :dollar_off,
            :duration_amount, :duration_unit, :end_date,
            true
        )
        RETURNING value_id
    """
    async with db_pool.session() as session:
        identity = await session.execute(
            text(identity_sql),
            {
                "gym_id": str(gym_id),
                "discount_name": name,
                "discount_type": discount_type,
            },
        )
        discount_id = UUID(str(identity.mappings().one()["discount_id"]))
        value = await session.execute(
            text(value_sql),
            {
                "discount_id": str(discount_id),
                "gym_id": str(gym_id),
                "percentage_off": percentage_off,
                "dollar_off": dollar_off,
                "duration_amount": duration_amount,
                "duration_unit": duration_unit,
                "end_date": end_date,
            },
        )
        value_id = UUID(str(value.mappings().one()["value_id"]))
        await session.commit()

    return TestDiscount(discount_id=discount_id, value_id=value_id)


# ── Reward ────────────────────────────────────────────────────


async def create_reward(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    *,
    title: str = "ZZ Test Reward",
    point_cost: int = 100,
    # gym_rewards.price_label / image_url are NOT NULL — default to the same
    # platform-default values the production create path fills in.
    price_label: str = "Free",
    image_url: str = settings.default_reward_image_url,
) -> TestReward:
    """Create a gym_rewards row directly.

    Unlike members/plans/discounts, a reward carries no Stripe object — it
    is plain gym config — so this is a single INSERT, no DB-first/Stripe
    round trip.
    """
    insert_reward_sql = """
        INSERT INTO gym_rewards (
            gym_id, title, point_cost, price_label, image_url
        ) VALUES (
            :gym_id, :title, :point_cost, :price_label, :image_url
        )
        RETURNING reward_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_reward_sql),
            {
                "gym_id": str(gym_id),
                "title": title,
                "point_cost": point_cost,
                "price_label": price_label,
                "image_url": image_url,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()

    return TestReward(reward_id=UUID(str(row["reward_id"])), gym_id=gym_id)
