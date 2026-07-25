"""The one-time charge window, seen from ``PaymentSyncOneTime``.

``tests/sync/test_one_time_writeback_resilience.py`` (C-025) locks the DOWNSTREAM
half of this guarantee: once ``create_invoice_payment`` has returned, a failing
writeback is swallowed so the caller never deletes the billed rows. These tests
lock the UPSTREAM half — the window *inside* ``create_invoice_payment`` itself,
which C-025's hardening sits below and therefore cannot protect.

``PaymentSyncOneTime._execute`` is a bare ``return await
self._payments.create_invoice_payment(...)`` and ``charge_one_time`` puts no
guard around it, so anything that raises out of the payment service lands in
``MemberMembershipsStart._charge_one_time_group``'s blanket ``except`` →
``_cleanup_states`` → ``_delete_pending``. If money had already been collected
when that raise happened, Stripe keeps it and the membership rows the member
paid for are deleted.

The halves of the invariant, asserted at this boundary:

1. a read failure propagates (so the caller cleans up) but must happen with
   NOTHING collected — the member is honestly told nothing happened;
2. once the money IS collected, nothing propagates — the rows survive;
3. and the mirror of (2): a pay that RETURNED without collecting (SCA / 3-D
   Secure) propagates a ``PaymentsNotCollectedError`` BEFORE ``_writeback``, so
   no row is ever stamped billed for money that never arrived.

Pure unit tests: the DB / payer collaborators are mocked and the payment
service runs for real over a fake Stripe client. Nothing touches a live DB or
Stripe.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.payments.payments_exceptions import PaymentsNotCollectedError
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.shared.payer_profile import PayerProfile
from src.sync.service.sync_one_time import PaymentSyncOneTime
from src.sync.sync_schema import OneTimeInvoiceItem, OneTimeInvoicePlan

STRIPE_ACCOUNT_ID = "acct_test_one_time_window"
CUSTOMER_ID = "cus_test_one_time_window"
INVOICE_ID = "in_test_one_time_window"
LINE_AMOUNT = 2500

# Stripe embeds only the first 10 lines on the invoice object, so a cart above
# that is what forces the separate line-items request — and a kiosk group
# signup (a large family, a class-pack) reaches it routinely.
EMBEDDED_PAGE = 10
PAGED_CART = 12


def _fake_stripe(
    *,
    n_items: int,
    line_items_error: Exception | None = None,
    broken_pay_result: bool = False,
    uncollected_pay: bool = False,
) -> MagicMock:
    """A Stripe double for the create -> finalize -> read -> pay sequence."""
    lines = []
    for index in range(n_items):
        line = MagicMock()
        line.id = f"il_{index}"
        line.parent.invoice_item_details.invoice_item = f"ii_{index}"
        line.subtotal = LINE_AMOUNT
        line.amount = LINE_AMOUNT
        line.discount_amounts = []
        lines.append(line)

    def invoice(status: str) -> MagicMock:
        inv = MagicMock()
        inv.id = INVOICE_ID
        inv.customer = CUSTOMER_ID
        inv.currency = "usd"
        inv.status = status
        inv.amount_paid = n_items * LINE_AMOUNT if status == "paid" else 0
        inv.metadata.to_dict.return_value = {}
        inv.lines.data = lines[:EMBEDDED_PAGE]
        inv.lines.has_more = n_items > EMBEDDED_PAGE
        return inv

    items = []
    for index in range(n_items):
        item = MagicMock()
        item.id = f"ii_{index}"
        items.append(item)

    if broken_pay_result:
        # A post-pay invoice the response model cannot be built from
        # (``customer`` is None): the money is collected, the assembly is not
        # possible, and a raise here would un-bill the charge.
        paid = MagicMock()
        paid.id = INVOICE_ID
        paid.customer = None
        paid.currency = "usd"
        paid.status = "paid"
        paid.amount_paid = n_items * LINE_AMOUNT
        paid.metadata = None
    elif uncollected_pay:
        # The pay RETURNED — no decline raised — but the invoice never reached
        # ``paid``: the off-session PaymentIntent needs SCA / 3-D Secure. No
        # money moved.
        paid = invoice("open")
    else:
        paid = invoice("paid")

    root = MagicMock()
    root.v1.invoices.create_async = AsyncMock(return_value=invoice("draft"))
    root.v1.invoice_items.create_async = AsyncMock(side_effect=items)
    root.v1.invoices.finalize_invoice_async = AsyncMock(
        return_value=invoice("open"),
    )
    root.v1.invoices.line_items.list_async = AsyncMock(
        side_effect=line_items_error,
        return_value=MagicMock(data=lines[EMBEDDED_PAGE:], has_more=False),
    )
    root.v1.invoices.pay_async = AsyncMock(return_value=paid)
    return root


def _plan(n_items: int) -> OneTimeInvoicePlan:
    """A one-time plan with ``n_items`` pending membership lines."""
    payer = PayerProfile(
        member_id=uuid4(),
        gym_id=uuid4(),
        stripe_customer_id=CUSTOMER_ID,
    )
    return OneTimeInvoicePlan(
        items=[
            OneTimeInvoiceItem(
                item_id=uuid4(),
                member_id=uuid4(),
                plan_id=uuid4(),
                stripe_price_id=f"price_{index}",
                quantity=1,
            )
            for index in range(n_items)
        ],
        payer=payer,
        stripe_account_id=STRIPE_ACCOUNT_ID,
        coupon_links={},
    )


def _make_service(
    plan: OneTimeInvoicePlan,
    root: MagicMock,
) -> PaymentSyncOneTime:
    """``PaymentSyncOneTime`` over a REAL payment service + a fake Stripe."""
    stripe_client = MagicMock()
    stripe_client.client = root
    stripe_client.connect_opts = PaymentsStripeClient.connect_opts
    stripe_client.connect_opts_readonly = (
        PaymentsStripeClient.connect_opts_readonly
    )
    payment_service = PaymentsStripePaymentService(stripe_client, AsyncMock())

    service = PaymentSyncOneTime(
        db_pool=MagicMock(),
        discounts=MagicMock(),
        payment_service=payment_service,
        payer_resolver=AsyncMock(),
    )
    service._queries = AsyncMock()
    # Skip the read/build; the window under test starts at the charge.
    service._build_plan = AsyncMock(return_value=plan)
    service._payer.resolve_payer_with_account = AsyncMock(
        return_value=(plan.payer, STRIPE_ACCOUNT_ID),
    )
    return service


@pytest.mark.asyncio
async def test_paged_line_read_failure_collects_nothing() -> None:
    """A >10-line cart whose line read fails must not have charged the card.

    This is the failure the old ordering turned into "Stripe keeps the money,
    the rows are deleted". The raise still propagates — that is correct, and
    it is what routes the caller to ``_cleanup_states`` — but it must now
    happen BEFORE any money moves, which makes deleting those un-billed rows
    the honest answer instead of a silent theft.
    """
    plan = _plan(PAGED_CART)
    root = _fake_stripe(
        n_items=PAGED_CART,
        line_items_error=RuntimeError("stripe line-items read blew up"),
    )
    service = _make_service(plan, root)

    with pytest.raises(RuntimeError):
        await service.charge_one_time(
            payer_member_id=plan.payer.member_id,
            idempotency_key=uuid4(),
        )

    root.v1.invoices.line_items.list_async.assert_awaited()
    root.v1.invoices.pay_async.assert_not_awaited()
    # Nothing was collected, so nothing was written back either.
    service._queries.apply_one_time_membership_sync.assert_not_awaited()


@pytest.mark.asyncio
async def test_post_collection_failure_never_reaches_the_caller() -> None:
    """Money collected -> ``charge_one_time`` returns, so the rows survive.

    ``charge_one_time`` returning cleanly is exactly what keeps
    ``_charge_one_time_group`` out of its ``except`` arm, so the just-billed
    membership rows are never deleted. The writeback still runs on the
    degraded response, so the rows keep their Stripe line ids.
    """
    plan = _plan(2)
    root = _fake_stripe(n_items=2, broken_pay_result=True)
    service = _make_service(plan, root)

    # Must NOT raise — a raise here un-bills a paid invoice in the caller.
    await service.charge_one_time(
        payer_member_id=plan.payer.member_id,
        idempotency_key=uuid4(),
    )

    root.v1.invoices.pay_async.assert_awaited_once()
    assert service._queries.apply_one_time_membership_sync.await_count == 2
    stamped = [
        call.kwargs["stripe_item_id"]
        for call in service._queries.apply_one_time_membership_sync.await_args_list
    ]
    assert stamped == ["il_0", "il_1"]


@pytest.mark.asyncio
async def test_uncollected_pay_writes_nothing_back() -> None:
    """The mirror invariant: nothing collected ⇒ no row may look billed.

    The writeback is the ONLY thing that makes a membership row look paid — it
    stamps ``stripe_item_id``, the consolidated invoice id and
    ``stripe_sync_status = 'applied'``. ``_execute`` is a bare ``return await``,
    so a raise from ``create_invoice_payment`` skips ``_writeback`` entirely and
    the rows stay ``not_added`` with a NULL ``stripe_item_id`` — provably
    un-billed, which is what makes the start op's cleanup of them correct.

    Before the collection guard, this exact scenario wrote back all three rows
    as ``applied`` off a ``status="open"`` response and the kiosk booked a
    membership nobody had paid for.
    """
    plan = _plan(3)
    root = _fake_stripe(n_items=3, uncollected_pay=True)
    service = _make_service(plan, root)

    with pytest.raises(PaymentsNotCollectedError):
        await service.charge_one_time(
            payer_member_id=plan.payer.member_id,
            idempotency_key=uuid4(),
        )

    root.v1.invoices.pay_async.assert_awaited_once()
    service._queries.apply_one_time_membership_sync.assert_not_awaited()


@pytest.mark.asyncio
async def test_paged_cart_charges_and_writes_back_every_line() -> None:
    """The happy >10-line path: charged once, all 12 rows stamped in order."""
    plan = _plan(PAGED_CART)
    root = _fake_stripe(n_items=PAGED_CART)
    service = _make_service(plan, root)

    await service.charge_one_time(
        payer_member_id=plan.payer.member_id,
        idempotency_key=uuid4(),
    )

    root.v1.invoices.pay_async.assert_awaited_once()
    stamped = [
        call.kwargs["stripe_item_id"]
        for call in service._queries.apply_one_time_membership_sync.await_args_list
    ]
    assert stamped == [f"il_{index}" for index in range(PAGED_CART)]
