"""Test data factory — create members, plans, prices, discounts.

Each function follows the production DB-first pattern:
INSERT with NULL stripe ID -> Stripe API -> UPDATE stripe ID.

Standalone module — no pytest imports, no fixture dependencies.
Every function accepts its dependencies as explicit parameters.
"""

from dataclasses import dataclass
from uuid import UUID

import stripe
from sqlalchemy import text

from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.database import DirectDatabasePool


# ── Return types ────────────────────────────────────────────────


@dataclass(frozen=True)
class TestMember:
    crm_user_id: UUID
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
    stripe_coupon_id: str


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
) -> TestMember:
    """Create a member profile with a Stripe customer (DB-first).

    1. INSERT into user_gym_profiles_unfiltered (stripe_customer_id = NULL)
    2. Create Stripe customer on connected account
    3. UPDATE profile with stripe_customer_id + card details
    """
    # Step 1: Insert pending row
    insert_sql = """
        INSERT INTO user_gym_profiles_unfiltered (
            gym_id, first_name, last_name
        ) VALUES (
            :gym_id, :first_name, :last_name
        )
        RETURNING crm_user_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {"gym_id": str(gym_id), "first_name": first_name, "last_name": last_name},
        )
        row = result.mappings().fetchone()
        await session.commit()
    crm_user_id = UUID(str(row["crm_user_id"]))

    # Step 2: Create Stripe customer
    customer_params: dict = {
        "name": f"{first_name} {last_name}",
        "metadata": {"crm_pk": str(crm_user_id)},
    }
    if payment_method_id:
        customer_params["payment_method"] = payment_method_id
        customer_params["invoice_settings"] = {
            "default_payment_method": payment_method_id,
        }

    customer = await stripe_client.client.v1.customers.create_async(
        params=customer_params,
        options=connect_opts,
    )

    # Step 3: Update profile with Stripe IDs
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
        UPDATE user_gym_profiles_unfiltered
        SET stripe_customer_id = :stripe_customer_id,
            stripe_payment_method_id = :stripe_pm_id,
            card_brand = :card_brand,
            card_last_four = :card_last_four,
            card_exp_month = :card_exp_month,
            card_exp_year = :card_exp_year
        WHERE crm_user_id = :crm_user_id
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
                "crm_user_id": str(crm_user_id),
            },
        )
        await session.commit()

    return TestMember(
        crm_user_id=crm_user_id,
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
    stripe_client: PaymentsStripeClient,
    gym_id: UUID,
    connect_opts: stripe.RequestOptions,
    *,
    name: str = "Test Discount",
    percentage_off: float | None = 10,
    dollar_off: int | None = None,
    duration: str = "forever",
    duration_in_months: int | None = None,
) -> TestDiscount:
    """Create a discount with Stripe coupon (DB-first).

    1. INSERT discount (stripe_coupon_id = NULL)
    2. Create Stripe coupon
    3. UPDATE discount with stripe_coupon_id
    """
    discount_type = "preset"

    # Step 1: Insert pending discount row
    insert_sql = """
        INSERT INTO gym_discounts_unfiltered (
            gym_id, discount_name, discount_type,
            percentage_off, dollar_off,
            duration, duration_in_months, is_deleted
        ) VALUES (
            :gym_id, :discount_name, :discount_type,
            :percentage_off, :dollar_off,
            :duration, :duration_in_months, false
        )
        RETURNING discount_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {
                "gym_id": str(gym_id),
                "discount_name": name,
                "discount_type": discount_type,
                "percentage_off": percentage_off,
                "dollar_off": dollar_off,
                "duration": duration,
                "duration_in_months": duration_in_months,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()
    discount_id = UUID(str(row["discount_id"]))

    # Step 2: Create Stripe coupon
    coupon_params: dict = {
        "name": name,
        "duration": duration,
        "metadata": {"crm_pk": str(discount_id)},
    }
    if percentage_off is not None:
        coupon_params["percent_off"] = percentage_off
    if dollar_off is not None:
        coupon_params["amount_off"] = dollar_off
        coupon_params["currency"] = "usd"
    if duration_in_months is not None:
        coupon_params["duration_in_months"] = duration_in_months

    coupon = await stripe_client.client.v1.coupons.create_async(
        params=coupon_params,
        options=connect_opts,
    )

    # Step 3: Update discount with stripe_coupon_id
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE gym_discounts_unfiltered "
                "SET stripe_coupon_id = :stripe_coupon_id "
                "WHERE discount_id = :discount_id"
            ),
            {"stripe_coupon_id": coupon.id, "discount_id": str(discount_id)},
        )
        await session.commit()

    return TestDiscount(
        discount_id=discount_id,
        stripe_coupon_id=coupon.id,
    )
