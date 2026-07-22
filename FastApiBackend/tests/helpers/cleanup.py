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
from pathlib import Path
from uuid import UUID

import stripe
from sqlalchemy import text

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_SQL_DIR = Path(__file__).resolve().parent / "sql"

# Tables in FK-safe deletion order (children before parents).
# ``member_charges`` cascades from ``member_invoices`` but is listed
# explicitly for defensive cleanup if a charge ever outlives its invoice.
# ``member_membership_applied_discounts_unfiltered`` (applied-discount rows)
# FK both the membership (item_id) and the member, so it is deleted first.
# ``member_authorized_payers`` FKs both members (member_id + payer_member_id)
# and a signature row, and ``member_waiver_signatures`` FKs members, so both go
# before ``members`` — the junction before the signatures it points at. The
# gym-config waivers themselves (gym_waivers / _versions) are left intact.
# ``member_activities`` FKs members with no cascade, so it goes last before
# ``members`` too.
_GYM_TABLES = (
    "stripe_webhook_events",
    "member_charges",
    "member_invoices",
    "member_membership_applied_discounts_unfiltered",
    "member_memberships_unfiltered",
    "membership_plan_prices_unfiltered",
    "gym_discounts_unfiltered",
    "membership_plans_unfiltered",
    "member_authorized_payers",
    "member_waiver_signatures",
    "member_activities",
    "members",
)


async def delete_all_gym_data(db_pool: DirectDatabasePool, gym_id: UUID) -> None:
    """Delete all test data for a gym in correct FK order.

    Does NOT delete the gym row itself — caller handles that.

    The applied-discounts table is deleted first like any other child. The
    family link lives in ``member_authorized_payers`` (in ``_GYM_TABLES`` before
    ``members``, ahead of the ``member_waiver_signatures`` it references);
    gym-config waivers stay.
    """
    async with db_pool.session() as session:
        for table in _GYM_TABLES:
            sql = load_sql(  # noqa: S608
                _SQL_DIR / "delete_gym_rows.sql", {"table": table}
            )
            await session.execute(text(sql), {"gym_id": str(gym_id)})
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
        # The ``stripe listen`` forwarding process can deliver an ``invoice.paid``
        # webhook to the running backend at any point, writing a new
        # ``member_invoice_line_items`` row that FKs the test membership via
        # ``fk_line_item_membership_gym``. That concurrent INSERT races the
        # membership DELETE below and causes a FK violation even if we deleted
        # line items earlier in this transaction — because all our deletes are
        # in one transaction, the membership row remains visible (READ COMMITTED)
        # to the webhook's separate connection until we commit.
        #
        # Fix: acquire an exclusive lock on ``member_invoice_line_items``
        # before deleting any rows. This blocks any concurrent INSERT/UPDATE
        # from the backend until we commit. When our commit lands the membership
        # is gone, so a blocked webhook retries later, resolves no member, and
        # returns early — a harmless logged error on the backend, not a bug.
        await session.execute(
            text(load_sql(_SQL_DIR / "lock_member_invoice_line_items.sql"))
        )
        # Billing rows are keyed by the PAYER (paid_by_member_id, the FK that
        # blocks the member delete); the beneficiary set lives on the invoice's
        # paid_for JSONB (no FK), so deleting by payer is what frees the row.
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_charges.sql")),
            {"id": str(member_id)},
        )
        # Invoice line items can reference THIS member's memberships from
        # ANOTHER member's invoice (family billing: a child's membership is
        # billed on the paying parent's invoice). Deleting only this member's
        # invoices misses those, so the membership delete below would hit
        # fk_line_item_membership_gym — delete them by membership item_id.
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_invoice_line_items_by_membership.sql")),
            {"id": str(member_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_invoices.sql")),
            {"id": str(member_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_applied_discounts.sql")),
            {"id": str(member_id)},
        )
        # Task records (e.g. a reprice task) FK both the member and their
        # membership rows, so they go before the memberships. A task whose
        # items are all removed goes too (tasks are per-gym, not per-member,
        # so only now-empty tasks are deleted).
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_task_items.sql")),
            {"id": str(member_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_empty_tasks.sql")),
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_memberships.sql")),
            {"id": str(member_id)},
        )
        # member_activities FKs the member with NO cascade
        # (fk_activity_member_gym), so any activity the member accrued blocks
        # the delete below. Points adjustments, rank changes and check-ins all
        # write one, so this is not an edge case — without this step the member
        # row survives teardown, orphaned in the shared seeded gym, and the
        # test that created it goes red on a ForeignKeyViolationError.
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_activities.sql")),
            {"id": str(member_id)},
        )
        # Authorization rows + waiver signatures FK the member (the junction also
        # FKs the signature it points at, so it goes first). Cover both roles:
        # the member as payee (member_id) and as payer (payer_member_id).
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_authorized_payers.sql")),
            {"id": str(member_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member_waiver_signatures.sql")),
            {"id": str(member_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_member.sql")),
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
            text(load_sql(_SQL_DIR / "delete_plan_prices.sql")),
            {"id": str(plan_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_plan.sql")),
            {"id": str(plan_id)},
        )
        await session.commit()


async def delete_reward_redemption(
    db_pool: DirectDatabasePool, redemption_id: UUID
) -> None:
    """Delete a single redemption row.

    A redemption row FKs BOTH the member (member_id, gym_id) and the reward
    (reward_id, gym_id) — call this before deleting either the member
    (``delete_member_data``) or the reward (``delete_reward``).
    """
    async with db_pool.session() as session:
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_reward_redemption.sql")),
            {"id": str(redemption_id)},
        )
        await session.commit()


async def delete_reward(db_pool: DirectDatabasePool, reward_id: UUID) -> None:
    """Delete a single gym_rewards row.

    Call AFTER any redemption rows referencing it are gone
    (``delete_reward_redemption``) — they FK this row.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_reward.sql")),
            {"id": str(reward_id)},
        )
        await session.commit()


async def delete_employee(
    db_pool: DirectDatabasePool, employee_id: UUID
) -> None:
    """Hard-delete a ``gym_employees`` row created by a test.

    Production soft-archives employees (``archived_at``); test teardown wants
    the row physically gone so created rows don't accumulate under the seeded
    gym across runs. Deletes regardless of ``archived_at`` (so it also removes
    a row a test already archived). A freshly-created test employee has no
    instructor / waiver-operator references, so a plain DELETE is safe. This
    hard DELETE is intentional and confined to the test suite.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_employee.sql")),
            {"id": str(employee_id)},
        )
        await session.commit()


async def delete_auth_user(db_pool: DirectDatabasePool, user_id: str) -> None:
    """Delete a Supabase ``auth.users`` row created by a test.

    A verified login is created for an employee via the admin API; teardown
    removes it by id directly on the local DB (the auth schema cascades the
    user's identities / sessions). There is no FK between ``auth.users`` and
    ``gym_employees`` (identity is email-based, no ``user_id`` column), so the
    order relative to ``delete_employee`` does not matter. Confined to the
    test suite.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_auth_user.sql")),
            {"id": str(user_id)},
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
            text(load_sql(_SQL_DIR / "delete_discount_values.sql")),
            {"id": str(discount_id)},
        )
        await session.execute(
            text(load_sql(_SQL_DIR / "delete_discount.sql")),
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
