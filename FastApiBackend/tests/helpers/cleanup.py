"""Database and Stripe cleanup utilities for integration tests.

Standalone module — no pytest imports, no fixture dependencies.
Every function accepts its dependencies as parameters.

The Stripe helpers are **best-effort**: a missing object
(``resource_missing`` — e.g. already removed by a test-clock cascade)
is swallowed silently, and any other Stripe error is logged as a
warning rather than raised, so one failed teardown step never masks a
test result or blocks the remaining cleanup.
"""

import logging
from uuid import UUID

import stripe
from sqlalchemy import text

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)

# Tables in FK-safe deletion order (children before parents).
# ``member_charges`` cascades from ``member_invoices`` but is listed
# explicitly for defensive cleanup if a charge ever outlives its invoice.
# ``member_membership_applied_discounts_unfiltered`` (applied-discount rows)
# FK both the membership (item_id) and the member, so it is deleted first.
_GYM_TABLES = (
    "stripe_webhook_events",
    "member_charges",
    "member_invoices",
    "member_membership_applied_discounts_unfiltered",
    "member_memberships_unfiltered",
    "membership_plan_prices_unfiltered",
    "gym_discounts_unfiltered",
    "membership_plans_unfiltered",
    "members",
)


async def delete_all_gym_data(db_pool: DirectDatabasePool, gym_id: UUID) -> None:
    """Delete all test data for a gym in correct FK order.

    Does NOT delete the gym row itself — caller handles that.

    ``account_linked_to_id`` (the family-billing self-link) is cleared before
    the members delete so the self-FK doesn't block.
    """
    async with db_pool.session() as session:
        await session.execute(
            text("UPDATE members SET account_linked_to_id = NULL WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )

        for table in _GYM_TABLES:
            await session.execute(
                text(f"DELETE FROM {table} WHERE gym_id = :gym_id"),  # noqa: S608
                {"gym_id": str(gym_id)},
            )
        await session.commit()


async def delete_member_data(
    db_pool: DirectDatabasePool,
    member_id: UUID,
) -> None:
    """Delete a single member, their billing rows, applied-discount rows,
    and their memberships, in FK-safe order.

    ``member_charges`` / ``member_invoices`` are written by the Stripe webhook
    mirror (e.g. an out-of-band cash invoice's ``invoice.paid`` lands in the
    shared local DB), so they can legitimately reference a test member and must
    be removed before the member row — charges FK invoices, so charges go first.
    The applied-discount rows FK both the membership and the member, so they are
    removed before the memberships and the member row.
    """
    async with db_pool.session() as session:
        # Billing rows are keyed by the PAYER (paid_by_member_id, the FK that
        # blocks the member delete); the beneficiary set lives on the invoice's
        # paid_for JSONB (no FK), so deleting by payer is what frees the row.
        await session.execute(
            text("DELETE FROM member_charges WHERE paid_by_member_id = :id"),
            {"id": str(member_id)},
        )
        # Invoice line items can reference THIS member's memberships from
        # ANOTHER member's invoice (family billing: a child's membership is
        # billed on the paying parent's invoice). Deleting only this member's
        # invoices misses those, so the membership delete below would hit
        # fk_line_item_membership_gym — delete them by membership item_id.
        await session.execute(
            text(
                "DELETE FROM member_invoice_line_items WHERE item_id IN "
                "(SELECT item_id FROM member_memberships_unfiltered "
                "WHERE member_id = :id)"
            ),
            {"id": str(member_id)},
        )
        await session.execute(
            text("DELETE FROM member_invoices WHERE paid_by_member_id = :id"),
            {"id": str(member_id)},
        )
        await session.execute(
            text(
                "DELETE FROM member_membership_applied_discounts_unfiltered WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        # Task records (e.g. a reprice task) FK both the member and their
        # membership rows, so they go before the memberships. A task whose
        # items are all removed goes too (tasks are per-gym, not per-member,
        # so only now-empty tasks are deleted).
        await session.execute(
            text("DELETE FROM task_items WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.execute(
            text(
                "DELETE FROM tasks WHERE NOT EXISTS "
                "(SELECT 1 FROM task_items ti WHERE ti.task_id = tasks.task_id)"
            ),
        )
        await session.execute(
            text("DELETE FROM member_memberships_unfiltered WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.execute(
            text("DELETE FROM members WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.commit()


async def delete_plan_data(db_pool: DirectDatabasePool, plan_id: UUID) -> None:
    """Delete a single membership plan and its prices (plan-scoped).

    Mirrors ``delete_member_data`` for the gym-level plan config that
    ``data_factory.create_plan`` inserts. Prices FK the plan, so they go
    first. Call AFTER ``delete_member_data`` for any member whose
    membership references one of this plan's prices.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM membership_plan_prices_unfiltered WHERE plan_id = :id"
            ),
            {"id": str(plan_id)},
        )
        await session.execute(
            text("DELETE FROM membership_plans_unfiltered WHERE plan_id = :id"),
            {"id": str(plan_id)},
        )
        await session.commit()


async def delete_discount_preset(
    db_pool: DirectDatabasePool, discount_id: UUID
) -> None:
    """Hard-delete a discount: its value versions, then the identity row.

    Production archives presets via ``is_deleted = true``; test teardown
    wants the rows physically gone so they do not accumulate under the
    seeded gym across runs. The versioned values live on
    ``gym_discount_values`` and FK the identity, so they are deleted first.
    Applied-discount rows reference ``value_id`` — delete the member's data
    (``delete_member_data``) BEFORE the discount so those FK refs are gone.
    This hard DELETE is intentional and confined to the test suite.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM gym_discount_values_unfiltered WHERE discount_id = :id"
            ),
            {"id": str(discount_id)},
        )
        await session.execute(
            text("DELETE FROM gym_discounts_unfiltered WHERE discount_id = :id"),
            {"id": str(discount_id)},
        )
        await session.commit()


# ── Stripe (best-effort) ────────────────────────────────────────


def _swallow_stripe(action: str, exc: stripe.StripeError) -> None:
    """Swallow ``resource_missing`` (already gone); warn on anything else."""
    if (
        isinstance(exc, stripe.InvalidRequestError)
        and getattr(exc, "code", None) == "resource_missing"
    ):
        return
    logger.warning("Test cleanup: %s failed: %s", action, exc)


async def delete_stripe_customer(
    stripe_client: PaymentsStripeClient,
    customer_id: str,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Delete a Stripe customer (cascades its subscriptions + invoices).

    Best-effort: a customer already removed by a test-clock cascade
    raises ``resource_missing``, which is swallowed.
    """
    try:
        await stripe_client.client.v1.customers.delete_async(
            customer_id, options=connect_opts
        )
    except stripe.StripeError as exc:
        _swallow_stripe(f"delete customer {customer_id}", exc)


async def delete_stripe_coupon(
    stripe_client: PaymentsStripeClient,
    coupon_id: str,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Delete a Stripe coupon (best-effort)."""
    try:
        await stripe_client.client.v1.coupons.delete_async(
            coupon_id, options=connect_opts
        )
    except stripe.StripeError as exc:
        _swallow_stripe(f"delete coupon {coupon_id}", exc)


async def archive_stripe_price(
    stripe_client: PaymentsStripeClient,
    price_id: str,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Archive a Stripe price (``active = false``) — prices can't be deleted.

    Best-effort: Stripe rejects archiving a price that is still its
    product's ``default_price``; that ``InvalidRequestError`` is logged
    and swallowed (archiving the product is the load-bearing cleanup).
    """
    try:
        await stripe_client.client.v1.prices.update_async(
            price_id, params={"active": False}, options=connect_opts
        )
    except stripe.StripeError as exc:
        _swallow_stripe(f"archive price {price_id}", exc)


async def archive_stripe_product(
    stripe_client: PaymentsStripeClient,
    product_id: str,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Archive a Stripe product (``active = false``) — can't delete one with prices."""
    try:
        await stripe_client.client.v1.products.update_async(
            product_id, params={"active": False}, options=connect_opts
        )
    except stripe.StripeError as exc:
        _swallow_stripe(f"archive product {product_id}", exc)
