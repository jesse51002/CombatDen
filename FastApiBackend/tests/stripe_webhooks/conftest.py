"""Stripe webhooks module fixtures.

Builds the dispatcher + handlers from plain constructors and sets up
the DB scaffolding (member, plan, price, synthetic membership row)
needed to exercise the event handlers against real tables.
"""

from dataclasses import dataclass
from uuid import UUID

import pytest
from sqlalchemy import text

from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.handlers.charge_refunded_handler import (
    ChargeRefundedHandler,
)
from src.stripe_webhooks.service.handlers.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.handlers.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.stripe_webhooks_service import (
    StripeWebhooksService,
)

from tests.helpers.data_factory import create_member, create_plan


# ── Service wiring (plain constructors, no DI container) ─────────


@pytest.fixture(scope="module")
def event_log() -> StripeWebhookEventLog:
    return StripeWebhookEventLog()


@pytest.fixture(scope="module")
def invoice_paid_handler() -> InvoicePaidHandler:
    return InvoicePaidHandler()


@pytest.fixture(scope="module")
def invoice_payment_failed_handler() -> InvoicePaymentFailedHandler:
    return InvoicePaymentFailedHandler()


@pytest.fixture(scope="module")
def charge_refunded_handler() -> ChargeRefundedHandler:
    return ChargeRefundedHandler()


@pytest.fixture(scope="module")
def stripe_webhooks_service(
    db_pool,
    event_log,
    invoice_paid_handler,
    invoice_payment_failed_handler,
    charge_refunded_handler,
) -> StripeWebhooksService:
    return StripeWebhooksService(
        db_pool=db_pool,
        event_log=event_log,
        invoice_paid_handler=invoice_paid_handler,
        invoice_payment_failed_handler=invoice_payment_failed_handler,
        charge_refunded_handler=charge_refunded_handler,
    )


# ── DB scaffolding for handler tests ─────────────────────────────


@dataclass(frozen=True)
class WebhookFixture:
    """A membership row fully wired up for webhook handler tests."""

    crm_user_id: UUID
    item_id: UUID
    stripe_item_id: str


@pytest.fixture(scope="module")
async def webhook_fixture(
    db_pool,
    stripe_client,
    connect_opts,
    gym_id,
) -> WebhookFixture:
    """Create a member, plan/price, and a membership with a synthetic
    ``stripe_item_id`` pointing at it.

    The ``stripe_item_id`` is a fake ``si_...`` value — handlers only
    use it to match rows, never to make Stripe API calls.
    """
    member = await create_member(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        first_name="Webhook",
        last_name="Fixture",
    )
    plan = await create_plan(
        db_pool,
        stripe_client,
        gym_id,
        connect_opts,
        plan_name="Webhook Fixture Plan",
        price_cents=5000,
    )

    stripe_item_id = f"si_test_webhook_{member.crm_user_id.hex[:12]}"
    insert_sql = """
        INSERT INTO member_memberships_unfiltered (
            crm_user_id, gym_id, plan_id, price_id,
            start_date, stripe_item_id, total_price
        ) VALUES (
            :crm_user_id, :gym_id, :plan_id, :price_id,
            CURRENT_DATE, :stripe_item_id, :total_price
        )
        RETURNING item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {
                "crm_user_id": str(member.crm_user_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "stripe_item_id": stripe_item_id,
                "total_price": plan.price_cents,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()

    return WebhookFixture(
        crm_user_id=member.crm_user_id,
        item_id=UUID(str(row["item_id"])),
        stripe_item_id=stripe_item_id,
    )


# ── Per-test cleanup of webhook-written rows ─────────────────────


@pytest.fixture(autouse=True)
async def _reset_webhook_tables(db_pool, gym_id):
    """Wipe webhook-owned rows between tests so ordering is irrelevant."""
    yield
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM stripe_webhook_events WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        await session.execute(
            text("DELETE FROM user_gym_charges WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        await session.execute(
            text("DELETE FROM user_gym_invoices WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        await session.execute(
            text(
                "UPDATE member_memberships_unfiltered "
                "SET last_paid_date = NULL, next_due_date = NULL "
                "WHERE gym_id = :gym_id"
            ),
            {"gym_id": str(gym_id)},
        )
        await session.commit()
