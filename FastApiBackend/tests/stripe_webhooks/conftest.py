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

from src.member_memberships.service.memberships.member_memberships_cancel_absorber import (
    SubscriptionCancellationAbsorber,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.gym_stripe_service import GymStripeService
from src.stripe_webhooks.service.account_updated_handler import (
    AccountUpdatedHandler,
)
from src.stripe_webhooks.service.customer_subscription_deleted_handler import (
    CustomerSubscriptionDeletedHandler,
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


# When set for a PI id, the fake returns an EXPANDED charge carrying this
# card last 4 (and method type 'card'); otherwise ``latest_charge`` is a bare
# charge-id string, matching a retrieve where the expand resolved nothing.
FAKE_PI_CARD_LAST4: dict[str, str] = {}


class _FakeCard:
    def __init__(self, last4: str) -> None:
        self.last4 = last4


class _FakePaymentMethodDetails:
    def __init__(self, type_: str, card: _FakeCard) -> None:
        self.type = type_
        self.card = card


class _FakeCharge:
    def __init__(self, charge_id: str, last4: str) -> None:
        self.id = charge_id
        self.payment_method_details = _FakePaymentMethodDetails(
            "card", _FakeCard(last4)
        )


class _FakePaymentIntent:
    def __init__(self, latest_charge: object) -> None:
        self.latest_charge = latest_charge


class _FakePaymentIntents:
    async def retrieve_async(
        self, payment_intent_id, params=None, options=None
    ):
        charge_id = fake_charge_id_for(payment_intent_id)
        last4 = FAKE_PI_CARD_LAST4.get(payment_intent_id)
        if last4 is not None:
            return _FakePaymentIntent(_FakeCharge(charge_id, last4))
        return _FakePaymentIntent(charge_id)


# Discounts the fake invoice-retrieve should return per invoice id, set by a
# test before dispatch: {stripe_invoice_id: [(di_id, coupon_id), ...]}. Used by
# the invoice.paid discount-audit capture (which retrieves the invoice with the
# coupon expanded). Empty by default → no discounts.
FAKE_INVOICE_DISCOUNTS: dict[str, list[tuple[str, str]]] = {}


class _FakeDiscountSource:
    """The dahlia Discount ``source`` — a discriminated union; for a coupon
    it carries the coupon id (a string) under ``coupon``."""

    def __init__(self, coupon_id: str) -> None:
        self.coupon = coupon_id
        self.type = "coupon"


class _FakeDiscount:
    def __init__(self, discount_id: str, coupon_id: str) -> None:
        self.id = discount_id
        self.source = _FakeDiscountSource(coupon_id)


class _FakeInvoice:
    def __init__(self, discounts: list[_FakeDiscount]) -> None:
        self.discounts = discounts


class _FakeInvoices:
    async def retrieve_async(self, invoice_id, params=None, options=None):
        pairs = FAKE_INVOICE_DISCOUNTS.get(invoice_id, [])
        return _FakeInvoice([_FakeDiscount(di, coupon) for di, coupon in pairs])


class _FakeStripeInner:
    def __init__(self) -> None:
        self.v1 = type(
            "V1",
            (),
            {
                "payment_intents": _FakePaymentIntents(),
                "invoices": _FakeInvoices(),
            },
        )()


class FakePaymentsStripeClient:
    """Stand-in for ``PaymentsStripeClient`` in webhook tests.

    ``.client`` exposes the PaymentIntent retrieve (``InvoicePaymentPaidHandler``)
    and the invoice retrieve with expanded coupons (``InvoicePaidHandler`` discount
    capture); ``connect_opts_readonly`` is the real pure staticmethod on
    ``PaymentsStripeClient``, so it needs no faking.
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
    # payment_sync uses the real test-account client; the discount-audit
    # retrieve is faked (the webhook test gym's account isn't real).
    return InvoicePaidHandler(
        payment_sync_service=build_payment_sync_service(db_pool, stripe_client),
        paying_lock=build_paying_member_lock(db_pool),
        stripe_client=FakePaymentsStripeClient(),
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
def customer_subscription_deleted_handler(
    db_pool,
) -> CustomerSubscriptionDeletedHandler:
    absorber = SubscriptionCancellationAbsorber(
        db_pool=db_pool,
        parent_resolver=BillingParentResolver(
            db_pool,
            GymStripeService(db_pool),
        ),
    )
    return CustomerSubscriptionDeletedHandler(cancellation_absorber=absorber)


@pytest.fixture(scope="module")
def stripe_webhooks_service(
    db_pool,
    event_log,
    invoice_paid_handler,
    invoice_payment_paid_handler,
    invoice_payment_failed_handler,
    refund_handler,
    account_updated_handler,
    customer_subscription_deleted_handler,
) -> StripeWebhooksService:
    return StripeWebhooksService(
        db_pool=db_pool,
        event_log=event_log,
        invoice_paid_handler=invoice_paid_handler,
        invoice_payment_paid_handler=invoice_payment_paid_handler,
        invoice_payment_failed_handler=invoice_payment_failed_handler,
        refund_handler=refund_handler,
        account_updated_handler=account_updated_handler,
        customer_subscription_deleted_handler=(
            customer_subscription_deleted_handler
        ),
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
