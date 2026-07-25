"""Unit tests for the two open-subscription-invoice pay paths (no network).

Both ``pay_open_subscription_invoice_out_of_band`` (cash) and
``pay_open_subscription_invoice_on_card`` (retry the saved default card) share
ONE open-invoice lookup, ``_list_open_subscription_invoices``. These tests pin
the load-bearing difference between them:

* the CARD path pays with EMPTY ``InvoicePayParams`` — no ``paid_out_of_band``
  and no ``payment_method``, which is exactly what makes Stripe charge the
  customer's saved default card — and stamps NO ``crm_paid_with_cash``
  metadata;
* the CASH path still stamps that metadata and still passes
  ``paid_out_of_band=True``;
* both raise the same errors from the shared lookup (unknown subscription →
  ``PaymentsResourceNotFoundError``; no open invoice → ``ValueError``);
* both RETURN the now-paid invoice (the plain nested dict the record seam
  consumes) so the settle can apply it in-request; the CARD path additionally
  refuses to return success when ``invoices.pay`` came back without collecting
  (SCA needs authentication) — a non-``paid`` return raises the DISTINCT
  ``PaymentsNotCollectedError`` rather than being booked as a phantom success.
  The type is load-bearing: the retry-card router answers it with its own 207
  ``not_collected`` result, while a base ``PaymentsStripeError`` is a 500.
"""

import json
from unittest.mock import AsyncMock, MagicMock

import pytest
import stripe

from src.payments.payments_exceptions import (
    PaymentsNotCollectedError,
    PaymentsResourceNotFoundError,
    PaymentsStripeError,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)

STRIPE_ACCOUNT_ID = "acct_test_open_invoice"
STRIPE_SUB_ID = "sub_test_open_invoice"
INVOICE_ID = "in_test_open_invoice"
IDEMPOTENCY_KEY = "11111111-1111-1111-1111-111111111111"


def _build_service(
    invoices: list | None = None,
    *,
    list_error: Exception | None = None,
) -> tuple[PaymentsStripePaymentService, MagicMock]:
    """Build the payment service over a fake Stripe client."""
    invoice = MagicMock()
    invoice.id = INVOICE_ID
    invoice.metadata.to_dict.return_value = {"existing": "kept"}

    invoices_list = [invoice] if invoices is None else invoices
    # ``invoices.pay`` returns the invoice you paid (invoices[0]), now settled.
    # Model that: the pay return carries a ``paid`` status and a JSON ``str()``
    # (the record seam consumes ``json.loads(str(invoice))``).
    paid = invoices_list[0] if invoices_list else invoice
    paid.status = "paid"
    paid.__str__.return_value = json.dumps({"id": paid.id, "status": "paid"})

    fake_stripe = MagicMock()
    fake_stripe.v1.invoices.list_async = AsyncMock(
        side_effect=list_error,
        return_value=MagicMock(data=invoices_list),
    )
    fake_stripe.v1.invoices.update_async = AsyncMock(return_value=paid)
    fake_stripe.v1.invoices.pay_async = AsyncMock(return_value=paid)

    stripe_client = MagicMock()
    stripe_client.client = fake_stripe
    stripe_client.connect_opts = PaymentsStripeClient.connect_opts
    stripe_client.connect_opts_readonly = (
        PaymentsStripeClient.connect_opts_readonly
    )

    service = PaymentsStripePaymentService(stripe_client, MagicMock())
    return service, fake_stripe


@pytest.mark.asyncio
async def test_on_card_pays_with_empty_params() -> None:
    """The card retry omits BOTH paid_out_of_band and payment_method."""
    service, fake_stripe = _build_service()

    result = await service.pay_open_subscription_invoice_on_card(
        STRIPE_SUB_ID,
        STRIPE_ACCOUNT_ID,
        idempotency_key=IDEMPOTENCY_KEY,
    )

    assert result == {"id": INVOICE_ID, "status": "paid"}
    fake_stripe.v1.invoices.pay_async.assert_awaited_once()
    call = fake_stripe.v1.invoices.pay_async.await_args
    assert call.args[0] == INVOICE_ID
    assert dict(call.kwargs["params"]) == {}
    assert call.kwargs["options"]["idempotency_key"] == f"{IDEMPOTENCY_KEY}:pay"
    assert call.kwargs["options"]["stripe_account"] == STRIPE_ACCOUNT_ID


@pytest.mark.asyncio
async def test_on_card_writes_no_cash_metadata() -> None:
    """A card retry must not stamp the crm_paid_with_cash flag."""
    service, fake_stripe = _build_service()

    await service.pay_open_subscription_invoice_on_card(
        STRIPE_SUB_ID,
        STRIPE_ACCOUNT_ID,
        idempotency_key=IDEMPOTENCY_KEY,
    )

    fake_stripe.v1.invoices.update_async.assert_not_awaited()


@pytest.mark.asyncio
async def test_out_of_band_still_stamps_cash_and_pays_out_of_band() -> None:
    """The cash path is unchanged by the shared-lookup extraction."""
    service, fake_stripe = _build_service()

    result = await service.pay_open_subscription_invoice_out_of_band(
        STRIPE_SUB_ID,
        STRIPE_ACCOUNT_ID,
        idempotency_key=IDEMPOTENCY_KEY,
    )

    assert result == {"id": INVOICE_ID, "status": "paid"}
    update_call = fake_stripe.v1.invoices.update_async.await_args
    assert update_call.kwargs["params"]["metadata"] == {
        "existing": "kept",
        "crm_paid_with_cash": "true",
    }
    pay_call = fake_stripe.v1.invoices.pay_async.await_args
    assert dict(pay_call.kwargs["params"]) == {"paid_out_of_band": True}


@pytest.mark.asyncio
async def test_both_paths_share_the_open_invoice_lookup() -> None:
    """One list call per pay, with the same subscription + open filter."""
    service, fake_stripe = _build_service()

    await service.pay_open_subscription_invoice_on_card(
        STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
    )
    await service.pay_open_subscription_invoice_out_of_band(
        STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
    )

    assert fake_stripe.v1.invoices.list_async.await_count == 2
    for call in fake_stripe.v1.invoices.list_async.await_args_list:
        params = call.kwargs["params"]
        assert params["subscription"] == STRIPE_SUB_ID
        assert params["status"] == "open"


@pytest.mark.asyncio
async def test_on_card_no_open_invoice_raises_without_leaking_stripe_id() -> None:
    """No open invoice is an ALREADY-SETTLED explanation, not a decline.

    This message reaches the front desk verbatim, in the slot reserved for
    the card-decline reason — so it must read as an explanation and must
    never surface a raw ``sub_...`` id as the reason a card "failed".
    """
    service, fake_stripe = _build_service(invoices=[])

    with pytest.raises(ValueError) as caught:
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID,
            STRIPE_ACCOUNT_ID,
            idempotency_key=IDEMPOTENCY_KEY,
        )

    message = str(caught.value)
    assert STRIPE_SUB_ID not in message, (
        f"the Stripe subscription id leaked to staff: {message!r}"
    )
    assert "sub_" not in message
    assert "already settled" in message.lower()
    # Must NOT contain "not found" — the router maps that substring to a 404.
    assert "not found" not in message.lower()

    fake_stripe.v1.invoices.pay_async.assert_not_awaited()


@pytest.mark.asyncio
async def test_on_card_unknown_subscription_raises_not_found() -> None:
    service, _fake_stripe = _build_service(
        list_error=stripe.InvalidRequestError("No such subscription", param=None),
    )

    with pytest.raises(PaymentsResourceNotFoundError, match="not found"):
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID,
            STRIPE_ACCOUNT_ID,
            idempotency_key=IDEMPOTENCY_KEY,
        )


@pytest.mark.asyncio
async def test_on_card_decline_propagates() -> None:
    """A CardError from pay_async is left to propagate, never swallowed."""
    service, fake_stripe = _build_service()
    fake_stripe.v1.invoices.pay_async.side_effect = stripe.CardError(
        "Your card was declined.",
        param=None,
        code="card_declined",
    )

    with pytest.raises(stripe.CardError):
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID,
            STRIPE_ACCOUNT_ID,
            idempotency_key=IDEMPOTENCY_KEY,
        )


@pytest.mark.asyncio
async def test_on_card_uncollected_return_raises_not_phantom_success() -> None:
    """A card retry that returns WITHOUT collecting must not be booked paid.

    ``invoices.pay`` raises ``CardError`` on an outright decline, but an
    off-session invoice needing authentication (SCA / 3-D Secure) can come back
    with the invoice still ``open`` and no exception. Booking that as success
    would clear the member off every overdue surface while no money moved, so
    the card path raises the DEDICATED ``PaymentsNotCollectedError``.

    The exact TYPE is the contract, not just "some error": the retry-card router
    answers this one with its own 207 ``not_collected`` result — a definitive
    business outcome, like a decline — whereas a plain ``PaymentsStripeError``
    stays a 500. Widening this assertion back to the base class would let a
    regression silently push a definitive outcome back onto the outage path.
    """
    service, fake_stripe = _build_service()
    uncollected = MagicMock()
    uncollected.status = "open"
    uncollected.__str__.return_value = json.dumps(
        {"id": INVOICE_ID, "status": "open"}
    )
    fake_stripe.v1.invoices.pay_async.return_value = uncollected

    with pytest.raises(PaymentsNotCollectedError, match="could not be charged"):
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )


@pytest.mark.asyncio
async def test_uncollected_error_is_not_mistaken_for_a_generic_stripe_error() -> None:
    """It IS a ``PaymentsStripeError`` (so an untaught caller still 500s it
    safely), which is exactly why the retry-card router must catch it ABOVE its
    base arm — otherwise the base wins and the 207 is unreachable."""
    service, fake_stripe = _build_service()
    uncollected = MagicMock()
    uncollected.status = "open"
    uncollected.__str__.return_value = json.dumps(
        {"id": INVOICE_ID, "status": "open"}
    )
    fake_stripe.v1.invoices.pay_async.return_value = uncollected

    with pytest.raises(PaymentsStripeError) as caught:
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )

    assert isinstance(caught.value, PaymentsNotCollectedError)
    # Not the not-found sibling — nothing is missing, the money just didn't move.
    assert not isinstance(caught.value, PaymentsResourceNotFoundError)


def _build_service_pay_error(exc: Exception) -> PaymentsStripePaymentService:
    """A service whose pay_async raises, but whose lookup succeeds."""
    invoice = MagicMock()
    invoice.id = INVOICE_ID
    invoice.metadata.to_dict.return_value = {}

    fake_stripe = MagicMock()
    fake_stripe.v1.invoices.list_async = AsyncMock(
        return_value=MagicMock(data=[invoice])
    )
    fake_stripe.v1.invoices.update_async = AsyncMock(return_value=invoice)
    fake_stripe.v1.invoices.pay_async = AsyncMock(side_effect=exc)

    stripe_client = MagicMock()
    stripe_client.client = fake_stripe
    stripe_client.connect_opts = PaymentsStripeClient.connect_opts
    stripe_client.connect_opts_readonly = (
        PaymentsStripeClient.connect_opts_readonly
    )
    return PaymentsStripePaymentService(stripe_client, MagicMock())


@pytest.mark.asyncio
async def test_pay_missing_invoice_maps_to_not_found() -> None:
    """A resource_missing on pay is genuinely a not-found invoice."""
    exc = stripe.InvalidRequestError("No such invoice", "id", code="resource_missing")
    service = _build_service_pay_error(exc)

    with pytest.raises(PaymentsResourceNotFoundError):
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )


@pytest.mark.asyncio
async def test_already_paid_invoice_is_not_flattened_to_not_found() -> None:
    """A SECOND retry on an already-paid invoice must surface Stripe's real
    message, not a misleading "Invoice ... not found".

    The bug this guards: any InvalidRequestError on pay was mapped to
    PaymentsResourceNotFoundError, so an idempotency-fresh retry of an
    already-settled invoice read as "not found" instead of "already paid".
    """
    exc = stripe.InvalidRequestError(
        "This invoice is already paid", "id", code="invoice_no_payment_required"
    )
    service = _build_service_pay_error(exc)

    with pytest.raises(PaymentsStripeError) as caught:
        await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )
    # A PaymentsStripeError, but NOT the not-found subclass, and it carries
    # Stripe's own message rather than a fabricated "not found".
    assert not isinstance(caught.value, PaymentsResourceNotFoundError)
    assert "already paid" in str(caught.value)


@pytest.mark.asyncio
async def test_cash_path_already_paid_also_surfaces_real_message() -> None:
    """The same classifier guards the cash path — the fix is shared."""
    exc = stripe.InvalidRequestError(
        "This invoice is already paid", "id", code="invoice_no_payment_required"
    )
    service = _build_service_pay_error(exc)

    with pytest.raises(PaymentsStripeError) as caught:
        await service.pay_open_subscription_invoice_out_of_band(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )
    assert not isinstance(caught.value, PaymentsResourceNotFoundError)
    assert "already paid" in str(caught.value)


@pytest.mark.asyncio
async def test_settle_pays_the_newest_of_a_stacked_backlog(caplog) -> None:
    """With several open invoices, the settle pays the NEWEST and says so.

    Stacking is rare (Stripe drafts/auto-closes later invoices while past_due,
    and the cancel end-action kills the sub inside the retry window), but the
    branch exists. The danger is silence: paying one advances next_due_date,
    which drops the member off every overdue surface while the rest stay
    unpaid. The lookup therefore returns ALL of them and logs the backlog.
    """
    def _open(invoice_id: str) -> MagicMock:
        inv = MagicMock()
        inv.id = invoice_id
        inv.amount_remaining = 12000
        inv.metadata.to_dict.return_value = {}
        return inv

    # Stripe lists newest-first.
    backlog = [_open("in_newest"), _open("in_older"), _open("in_oldest")]
    service, fake_stripe = _build_service(invoices=backlog)

    with caplog.at_level("WARNING"):
        result = await service.pay_open_subscription_invoice_on_card(
            STRIPE_SUB_ID, STRIPE_ACCOUNT_ID, idempotency_key=IDEMPOTENCY_KEY
        )

    # Stripe lists newest-first, so [0] is what gets settled and returned.
    assert result["id"] == "in_newest"
    assert fake_stripe.v1.invoices.pay_async.await_args.args[0] == "in_newest"
    # The backlog is surfaced, not swallowed.
    messages = [r.getMessage() for r in caplog.records]
    assert any("3 open invoices" in m for m in messages), (
        f"expected a backlog warning, got: {messages}"
    )
    assert any("36000" in m for m in messages), (
        "the warning must state the total still owed"
    )
