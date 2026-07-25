"""The money window in ``create_invoice_payment``: read first, THEN charge.

``create_invoice_payment`` collects real money at ``invoices.pay``. Everything
that runs after that call sits in a window where a raise cannot be undone:
Stripe keeps the money, while the exception propagates out through
``PaymentSyncOneTime`` to ``MemberMembershipsStart._charge_one_time_group``,
whose blanket ``except`` deletes the just-billed membership rows. That is the
exact failure ``PaymentSyncOneTime._writeback`` was hardened against (C-025) —
but the hardening sits DOWNSTREAM of the payment service, so a raise from
inside the payment service never reaches it.

Two things used to live in that window and both can raise:

* ``_all_invoice_lines`` makes a NETWORK call whenever ``invoice.lines.has_more``
  is true — i.e. a cart of more than 10 lines, which a kiosk group signup makes
  ordinary (a large family, a class-pack).
* ``_order_lines`` raises ``PaymentsStripeError`` for a genuinely absent
  invoice item.

Both reads now run right after FINALIZE, before the pay. Finalizing is what
creates the lines and paying never alters them (verified live against the
pinned dahlia API), so the map is identical either way — and a failure there
costs the member nothing, because nothing has been charged and the caller's
cleanup of un-billed rows is then correct.

These are pure unit tests over a fake Stripe client — no network, no DB.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)

STRIPE_ACCOUNT_ID = "acct_test_charge_ordering"
CUSTOMER_ID = "cus_test_charge_ordering"
INVOICE_ID = "in_test_charge_ordering"
LINE_AMOUNT = 1000

# Stripe embeds only the first page of lines on the invoice object (10 by
# default), so this is the smallest cart that flips ``lines.has_more`` and
# forces the separate, paginated line-items request.
EMBEDDED_PAGE = 10
PAGED_CART = 12

CREATE = "invoice.create"
ITEM = "invoice_item.create"
FINALIZE = "invoice.finalize"
LIST_LINES = "invoice.line_items.list"
PAY = "invoice.pay"


def _line(index: int) -> MagicMock:
    """One finalized invoice line pointing back at the InvoiceItem behind it."""
    line = MagicMock()
    line.id = f"il_{index}"
    line.parent.invoice_item_details.invoice_item = f"ii_{index}"
    line.subtotal = LINE_AMOUNT
    line.amount = LINE_AMOUNT
    line.discount_amounts = []
    return line


class _FakeStripe:
    """A Stripe client double that records the ORDER of every call made."""

    def __init__(
        self,
        *,
        n_items: int,
        n_lines: int,
        line_items_error: Exception | None,
        zero_amount: bool,
    ) -> None:
        self.calls: list[str] = []
        lines = [_line(i) for i in range(n_lines)]

        def invoice(status: str) -> MagicMock:
            inv = MagicMock()
            inv.id = INVOICE_ID
            inv.customer = CUSTOMER_ID
            inv.currency = "usd"
            inv.status = status
            inv.amount_paid = n_lines * LINE_AMOUNT if status == "paid" else 0
            inv.metadata.to_dict.return_value = {}
            inv.lines.data = lines[:EMBEDDED_PAGE]
            inv.lines.has_more = n_lines > EMBEDDED_PAGE
            return inv

        # A zero-amount invoice comes back from finalize already ``paid``, so
        # the pay step is skipped entirely.
        self.root = MagicMock()
        self.root.v1.invoices.create_async = self._step(CREATE, invoice("draft"))
        self.root.v1.invoice_items.create_async = self._items(n_items)
        self.root.v1.invoices.finalize_invoice_async = self._step(
            FINALIZE, invoice("paid" if zero_amount else "open")
        )
        self.root.v1.invoices.line_items.list_async = self._step(
            LIST_LINES,
            MagicMock(data=lines[EMBEDDED_PAGE:], has_more=False),
            error=line_items_error,
        )
        self.root.v1.invoices.pay_async = self._step(PAY, invoice("paid"))

    def _step(
        self,
        name: str,
        result: object,
        *,
        error: Exception | None = None,
    ) -> AsyncMock:
        async def call(*_args: object, **_kwargs: object) -> object:
            self.calls.append(name)
            if error is not None:
                raise error
            return result

        return AsyncMock(side_effect=call)

    def _items(self, n_items: int) -> AsyncMock:
        created = []
        for index in range(n_items):
            item = MagicMock()
            item.id = f"ii_{index}"
            created.append(item)
        counter = iter(created)

        async def call(*_args: object, **_kwargs: object) -> object:
            self.calls.append(ITEM)
            return next(counter)

        return AsyncMock(side_effect=call)


def _build_service(
    *,
    n_items: int,
    n_lines: int | None = None,
    line_items_error: Exception | None = None,
    zero_amount: bool = False,
) -> tuple[PaymentsStripePaymentService, _FakeStripe]:
    """Build the payment service over the recording Stripe double.

    ``n_lines`` defaults to ``n_items`` (the normal case: Stripe produces one
    line per InvoiceItem); passing fewer models the absent-line failure.
    """
    fake = _FakeStripe(
        n_items=n_items,
        n_lines=n_items if n_lines is None else n_lines,
        line_items_error=line_items_error,
        zero_amount=zero_amount,
    )
    stripe_client = MagicMock()
    stripe_client.client = fake.root
    stripe_client.connect_opts = PaymentsStripeClient.connect_opts
    stripe_client.connect_opts_readonly = (
        PaymentsStripeClient.connect_opts_readonly
    )
    service = PaymentsStripePaymentService(stripe_client, AsyncMock())
    return service, fake


def _request(n_items: int) -> PaymentsInvoicePaymentCreateRequest:
    """A cart of ``n_items`` price lines."""
    return PaymentsInvoicePaymentCreateRequest(
        stripe_customer_id=CUSTOMER_ID,
        items=[
            PaymentsInvoiceItemSpec(stripe_price_id=f"price_{i}")
            for i in range(n_items)
        ],
        metadata=StripeMembershipOneTimeMetadata(
            paid_by_member_id=uuid4(),
            paid_for=[uuid4()],
            gym_id=uuid4(),
        ),
        idempotency_key=str(uuid4()),
    )


def _broken_invoice(status: object, amount_paid: object) -> MagicMock:
    """A post-pay invoice the response model cannot be built from.

    ``customer`` is None, which fails ``stripe_customer_id: str`` validation;
    everything else is left readable so the fallback's own reads are what the
    test observes.
    """
    invoice = MagicMock()
    invoice.id = INVOICE_ID
    invoice.customer = None
    invoice.currency = "usd"
    invoice.status = status
    invoice.amount_paid = amount_paid
    invoice.metadata = None
    return invoice


# ── Read before charging ────────────────────────────────────────────


@pytest.mark.asyncio
async def test_paged_line_read_failure_does_not_charge_the_card() -> None:
    """A >10-line cart whose line-items read fails must NOT have collected.

    THE regression guard for the money window. With the reads sitting after
    the pay, this exact scenario charged the customer and THEN raised, and the
    raise reached ``MemberMembershipsStart``'s blanket ``except`` →
    ``_cleanup_states`` → ``_delete_pending``: Stripe kept the money and the
    membership rows the member had just paid for were deleted.

    The invariant is asserted as its contrapositive, which is the testable
    form: the failure that triggers the caller's row cleanup must happen while
    NOTHING has been collected — so the pay must never have been attempted.
    """
    service, fake = _build_service(
        n_items=PAGED_CART,
        line_items_error=RuntimeError("stripe line-items read blew up"),
    )

    with pytest.raises(RuntimeError):
        await service.create_invoice_payment(
            _request(PAGED_CART), STRIPE_ACCOUNT_ID
        )

    # The read really did go over the network — the >10-line cart is what
    # makes that request reachable at all — and it really did fail...
    assert LIST_LINES in fake.calls
    # ...and no money moved, so the caller deleting its un-billed rows is
    # correct and the member is honestly told nothing happened.
    fake.root.v1.invoices.pay_async.assert_not_awaited()
    assert PAY not in fake.calls


@pytest.mark.asyncio
async def test_absent_invoice_line_does_not_charge_the_card() -> None:
    """``_order_lines``' raise is the other door into the same room.

    It is pure Python, but it raises ``PaymentsStripeError`` for an invoice
    item with no matching line — so on the old ordering it too fired after the
    money was collected.
    """
    service, fake = _build_service(n_items=3, n_lines=2)

    with pytest.raises(PaymentsStripeError):
        await service.create_invoice_payment(_request(3), STRIPE_ACCOUNT_ID)

    fake.root.v1.invoices.pay_async.assert_not_awaited()
    assert PAY not in fake.calls


@pytest.mark.asyncio
async def test_no_stripe_call_happens_after_the_pay() -> None:
    """The ordering invariant, pinned structurally on the recorded call order.

    Once ``invoices.pay`` returns, the response is assembled from objects
    already in hand — no further Stripe request may be issued. Asserting the
    exact sequence means a future refactor that moves a read back below the
    charge fails loudly here instead of silently re-opening the window.
    """
    service, fake = _build_service(n_items=PAGED_CART)

    await service.create_invoice_payment(
        _request(PAGED_CART), STRIPE_ACCOUNT_ID
    )

    assert fake.calls == (
        [CREATE] + [ITEM] * PAGED_CART + [FINALIZE, LIST_LINES, PAY]
    )
    assert fake.calls[-1] == PAY, (
        "a Stripe call runs after the money is collected: "
        f"{fake.calls[fake.calls.index(PAY) + 1:]}"
    )


@pytest.mark.asyncio
async def test_small_cart_makes_no_extra_line_items_request() -> None:
    """Under the embedded page size the pre-read costs no extra request."""
    service, fake = _build_service(n_items=3)

    resp = await service.create_invoice_payment(_request(3), STRIPE_ACCOUNT_ID)

    fake.root.v1.invoices.line_items.list_async.assert_not_awaited()
    assert fake.calls == [CREATE, ITEM, ITEM, ITEM, FINALIZE, PAY]
    assert resp.line_item_ids == ["il_0", "il_1", "il_2"]
    assert resp.line_amounts == [LINE_AMOUNT] * 3


@pytest.mark.asyncio
async def test_paged_cart_maps_every_line_in_request_order() -> None:
    """The >10-line map is complete and ordered, read from before the charge."""
    service, _fake = _build_service(n_items=PAGED_CART)

    resp = await service.create_invoice_payment(
        _request(PAGED_CART), STRIPE_ACCOUNT_ID
    )

    assert resp.line_item_ids == [f"il_{i}" for i in range(PAGED_CART)]
    assert resp.line_amounts == [LINE_AMOUNT] * PAGED_CART


@pytest.mark.asyncio
async def test_zero_amount_invoice_still_skips_the_pay_and_maps_lines() -> None:
    """The $0 path: already ``paid`` at finalize, so no pay — lines still map.

    Reading the lines before the pay must not disturb the branch that skips
    the pay entirely (paying an already-paid invoice raises "Invoice is
    already paid").
    """
    service, fake = _build_service(n_items=2, zero_amount=True)

    resp = await service.create_invoice_payment(_request(2), STRIPE_ACCOUNT_ID)

    fake.root.v1.invoices.pay_async.assert_not_awaited()
    assert fake.calls == [CREATE, ITEM, ITEM, FINALIZE]
    assert resp.status == "paid"
    assert resp.line_item_ids == ["il_0", "il_1"]


# ── The backstop: nothing may raise past the point of collection ────


@pytest.mark.asyncio
async def test_response_assembly_failure_after_pay_never_raises() -> None:
    """A broken post-pay invoice object must not un-bill a collected charge.

    With the reads moved, the assembly is pure attribute access and should not
    be able to fail — the guard exists for what a raise past collection COSTS,
    not because one is expected.
    """
    service, fake = _build_service(n_items=2)
    fake.root.v1.invoices.pay_async = AsyncMock(
        return_value=_broken_invoice(status=None, amount_paid=None),
    )

    resp = await service.create_invoice_payment(_request(2), STRIPE_ACCOUNT_ID)

    # Degraded, but never a raise — and built only from what is known.
    assert resp.stripe_invoice_id == INVOICE_ID
    assert resp.stripe_customer_id == CUSTOMER_ID
    assert resp.line_item_ids == ["il_0", "il_1"]
    assert resp.line_amounts == [LINE_AMOUNT, LINE_AMOUNT]
    assert resp.amount_paid == 2 * LINE_AMOUNT


@pytest.mark.asyncio
async def test_degraded_response_keeps_the_invoices_own_status() -> None:
    """The fallback prefers what the invoice says over assuming success."""
    service, fake = _build_service(n_items=1)
    fake.root.v1.invoices.pay_async = AsyncMock(
        return_value=_broken_invoice(status="open", amount_paid=0),
    )

    resp = await service.create_invoice_payment(_request(1), STRIPE_ACCOUNT_ID)

    assert resp.status == "open"
    assert resp.amount_paid == 0
