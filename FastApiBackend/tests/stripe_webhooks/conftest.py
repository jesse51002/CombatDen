"""Stripe webhooks module fixtures.

Builds the dispatcher + handlers from plain constructors and sets up
the DB scaffolding (member, plan, price, synthetic membership row)
needed to exercise the event handlers against real tables.
"""

import uuid
from dataclasses import dataclass
from uuid import UUID

import pytest
from sqlalchemy import text

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.stripe_webhooks.service.account_updated_handler import (
    AccountUpdatedHandler,
)
from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)
from src.stripe_webhooks.service.refund_handler import (
    RefundHandler,
)
from src.stripe_webhooks.service.stripe_webhooks_service import (
    StripeWebhooksService,
)
from tests.conftest import STRIPE_TEST_ACCOUNT_ID
from tests.helpers.cleanup import delete_all_gym_data
from tests.helpers.data_factory import create_member, create_plan
from tests.helpers.service_factory import (
    build_paying_member_lock,
    build_payment_sync_service,
)

# Synthetic stripe_account_id for webhook tests only. The seed script
# inserts several gyms pointing at the real test account; if the
# webhook handler's ``gym_by_stripe_account`` lookup resolves to one
# of those seeded gyms instead of our freshly inserted test gym,
# every ``invoice.paid`` event would hit "no membership matched".
# We decouple by giving the webhook test gym a unique id here, while
# ``connect_opts`` below continues to target the real Stripe Connect
# account so ``create_member`` / ``create_plan`` still work.
_WEBHOOK_STRIPE_ACCOUNT_ID = f"acct_webhook_test_{uuid.uuid4().hex[:16]}"


def fake_charge_id_for(payment_intent_id: str) -> str:
    """The charge id the fake Stripe client resolves a PaymentIntent to.

    ``InvoicePaymentPaidHandler`` retrieves the PaymentIntent and reads
    ``latest_charge``; the fake below derives it deterministically so tests
    can assert on (and refund) the resulting ``member_charges`` row.
    """
    return f"ch_for_{payment_intent_id}"


class _FakePaymentIntent:
    def __init__(self, latest_charge: str) -> None:
        self.latest_charge = latest_charge


class _FakePaymentIntents:
    async def retrieve_async(self, payment_intent_id, options=None):
        return _FakePaymentIntent(fake_charge_id_for(payment_intent_id))


class _FakeStripeInner:
    def __init__(self) -> None:
        self.v1 = type("V1", (), {"payment_intents": _FakePaymentIntents()})()


class FakePaymentsStripeClient:
    """Stand-in for ``PaymentsStripeClient`` in webhook tests.

    Only ``.client`` is exercised by ``InvoicePaymentPaidHandler`` (the
    PaymentIntent retrieve); ``connect_opts_readonly`` is the real pure
    staticmethod on ``PaymentsStripeClient``, so it needs no faking.
    """

    @property
    def client(self) -> _FakeStripeInner:
        return _FakeStripeInner()


# ── Overrides to isolate from seeded gyms sharing the real test account ──


@pytest.fixture(scope="module")
def stripe_account_id() -> str:
    """Override the session-scoped fixture with a webhook-only id."""
    return _WEBHOOK_STRIPE_ACCOUNT_ID


@pytest.fixture(scope="module")
def connect_opts(stripe_client):
    """Override: use the REAL Stripe test account for actual API calls.

    The gym row stores the synthetic ``_WEBHOOK_STRIPE_ACCOUNT_ID``
    so the webhook resolver finds it uniquely, but anything that
    hits the Stripe API (``create_member``, ``create_plan``) still
    needs to target a real connected account.
    """
    return PaymentsStripeClient.connect_opts_readonly(STRIPE_TEST_ACCOUNT_ID)


@pytest.fixture(scope="module")
async def gym_id(db_pool, stripe_account_id):
    """Override: insert a dedicated webhook test gym and tear it down.

    Uses the synthetic ``stripe_account_id`` so the
    ``gym_by_stripe_account`` resolver in ``StripeWebhooksService``
    uniquely matches this row, ignoring any seed-data gyms.
    """
    insert_sql = """
        INSERT INTO gyms (gym_name, stripe_account_id, stripe_onboarding_status)
        VALUES (:name, :stripe_account_id, 'complete')
        RETURNING gym_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {
                "name": "Webhook Test Gym",
                "stripe_account_id": stripe_account_id,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()

    gid = UUID(str(row["gym_id"]))
    yield gid

    await delete_all_gym_data(db_pool, gid)
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM gyms WHERE gym_id = :gym_id"),
            {"gym_id": str(gid)},
        )
        await session.commit()


# ── Service wiring (plain constructors, no DI container) ─────────


@pytest.fixture(scope="module")
def event_log() -> StripeWebhookEventLog:
    return StripeWebhookEventLog()


@pytest.fixture(scope="module")
def invoice_paid_handler(db_pool, stripe_client) -> InvoicePaidHandler:
    return InvoicePaidHandler(
        payment_sync_service=build_payment_sync_service(db_pool, stripe_client),
        paying_lock=build_paying_member_lock(db_pool),
    )


@pytest.fixture(scope="module")
def invoice_payment_paid_handler() -> InvoicePaymentPaidHandler:
    # Fake Stripe client: the PaymentIntent retrieve is the only Stripe call,
    # and the webhook test gym uses a synthetic account a real retrieve can't
    # hit. The live E2E exercises the real retrieve.
    return InvoicePaymentPaidHandler(stripe_client=FakePaymentsStripeClient())


@pytest.fixture(scope="module")
def invoice_payment_failed_handler() -> InvoicePaymentFailedHandler:
    return InvoicePaymentFailedHandler()


@pytest.fixture(scope="module")
def refund_handler() -> RefundHandler:
    return RefundHandler()


@pytest.fixture(scope="module")
def account_updated_handler() -> AccountUpdatedHandler:
    return AccountUpdatedHandler()


@pytest.fixture(scope="module")
def stripe_webhooks_service(
    db_pool,
    event_log,
    invoice_paid_handler,
    invoice_payment_paid_handler,
    invoice_payment_failed_handler,
    refund_handler,
    account_updated_handler,
) -> StripeWebhooksService:
    return StripeWebhooksService(
        db_pool=db_pool,
        event_log=event_log,
        invoice_paid_handler=invoice_paid_handler,
        invoice_payment_paid_handler=invoice_payment_paid_handler,
        invoice_payment_failed_handler=invoice_payment_failed_handler,
        refund_handler=refund_handler,
        account_updated_handler=account_updated_handler,
    )


# ── DB scaffolding for handler tests ─────────────────────────────


@dataclass(frozen=True)
class WebhookFixture:
    """A membership row fully wired up for webhook handler tests."""

    member_id: UUID
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

    stripe_item_id = f"si_test_webhook_{member.member_id.hex[:12]}"
    # A live, synced membership is stamped 'applied' by the sync writeback — set
    # it here so the row is visible through the client-facing `member_memberships`
    # view that the webhook's `membership_by_stripe_item.sql` resolver reads
    # (the view hides 'not_added', which is the column default).
    insert_sql = """
        INSERT INTO member_memberships_unfiltered (
            member_id, gym_id, plan_id, price_id,
            start_date, stripe_item_id, total_price, stripe_sync_status
        ) VALUES (
            :member_id, :gym_id, :plan_id, :price_id,
            CURRENT_DATE, :stripe_item_id, :total_price, 'applied'
        )
        RETURNING item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {
                "member_id": str(member.member_id),
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
        member_id=member.member_id,
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
            text("DELETE FROM member_charges WHERE gym_id = :gym_id"),
            {"gym_id": str(gym_id)},
        )
        await session.execute(
            text("DELETE FROM member_invoices WHERE gym_id = :gym_id"),
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
