"""Stripe billing assertion helpers for integration tests.

Standalone module — mirrors the pattern in ``stripe_clock.py``:
no pytest imports, no fixture dependencies. Every function accepts
its Stripe client and connect options explicitly so the helpers can
be called from any test without wiring new fixtures.

Typical flow for a mid-cycle edit test:

    before = await snapshot_billing_state(
        stripe_client, customer_id, connect_opts,
    )
    await service.do_the_mid_cycle_thing(...)
    await assert_no_unexpected_charges(stripe_client, before, connect_opts)

    sub = await fetch_subscription(
        stripe_client, sub_id, connect_opts,
    )
    assert_subscription_item_price(sub, expected_price_id)

    invoice = await advance_to_next_cycle_and_fetch_invoice(
        stripe_client, clock_id, next_cycle_dt, sub_id, before, connect_opts,
    )
    assert_invoice_matches(invoice, amount_due=expected_amount)
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime

import stripe

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from tests.helpers.stripe_clock import advance_clock

INVOICE_POLL_INTERVAL_S = 1.0
INVOICE_POLL_MAX_WAIT_S = 60
INVOICE_LIST_LIMIT = 100
SUBSCRIPTION_EXPAND_DEFAULTS: tuple[str, ...] = (
    "items.data.price",
    "items.data.discounts",
    "discounts",
)


@dataclass(frozen=True)
class BillingSnapshot:
    """Snapshot of a customer's Stripe billing state at one point in time.

    Attributes:
        customer_id: The Stripe customer the snapshot belongs to.
        invoice_ids: IDs of every invoice that existed at snapshot time.
        open_invoice_count: Count of invoices in status ``open``.
        customer_balance: Customer balance in the smallest currency unit.
    """

    customer_id: str
    invoice_ids: frozenset[str]
    open_invoice_count: int
    customer_balance: int


async def snapshot_billing_state(
    stripe_client: PaymentsStripeClient,
    customer_id: str,
    connect_opts: stripe.RequestOptions,
) -> BillingSnapshot:
    """Capture the current Stripe billing state for a customer.

    Call this before a mid-cycle operation that must not charge
    the member. Pair with :func:`assert_no_unexpected_charges` to
    confirm the operation did not create new invoices or shift
    the customer balance.
    """
    invoice_ids, open_count = await _list_invoice_ids_and_open_count(
        stripe_client,
        customer_id,
        connect_opts,
    )
    customer = await stripe_client.client.v1.customers.retrieve_async(
        customer_id,
        options=connect_opts,
    )
    return BillingSnapshot(
        customer_id=customer_id,
        invoice_ids=frozenset(invoice_ids),
        open_invoice_count=open_count,
        customer_balance=customer.balance or 0,
    )


async def assert_no_unexpected_charges(
    stripe_client: PaymentsStripeClient,
    before: BillingSnapshot,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Assert no new Stripe charges landed since ``before``.

    Checks:
        * No new invoice ids appeared.
        * The number of open invoices did not change.
        * The customer balance did not change.

    Raises:
        AssertionError with a detailed diff on any change.
    """
    after_ids, after_open = await _list_invoice_ids_and_open_count(
        stripe_client,
        before.customer_id,
        connect_opts,
    )
    customer = await stripe_client.client.v1.customers.retrieve_async(
        before.customer_id,
        options=connect_opts,
    )
    new_ids = set(after_ids) - before.invoice_ids
    assert not new_ids, (
        f"Unexpected new invoice(s) created for customer {before.customer_id}: {sorted(new_ids)}"
    )
    assert after_open == before.open_invoice_count, (
        f"Open invoice count changed for customer {before.customer_id}: "
        f"before={before.open_invoice_count} after={after_open}"
    )
    assert (customer.balance or 0) == before.customer_balance, (
        f"Customer balance changed for {before.customer_id}: "
        f"before={before.customer_balance} after={customer.balance}"
    )


async def assert_immediate_prorated_invoice(
    stripe_client: PaymentsStripeClient,
    before: BillingSnapshot,
    connect_opts: stripe.RequestOptions,
    *,
    subscription_id: str,
    min_amount: int = 1,
    max_amount: int | None = None,
    expect_paid: bool = True,
) -> stripe.Invoice:
    """Assert exactly one new invoice was cut for ``subscription_id``.

    Complement of :func:`assert_no_unexpected_charges` for operations
    that are expected to bill immediately (e.g. membership start with
    ``prorate=True`` or a mid-cycle upgrade with ``prorate=True``).

    Checks:
        * Exactly one new invoice id appeared for the customer.
        * That invoice belongs to ``subscription_id``.
        * ``min_amount <= invoice.amount_due <= max_amount`` when
          ``max_amount`` is provided; otherwise just the lower bound.
          Pass ``min_amount=0`` to allow a zero-dollar invoice
          (e.g. a $0 plan).
        * When ``expect_paid`` is True, ``invoice.status == "paid"``
          and ``invoice.amount_paid == invoice.amount_due``.

    Returns:
        The new invoice — callers can chain further line-item
        assertions on it.

    Raises:
        AssertionError with a detailed diff on any mismatch.
    """
    after_ids, _ = await _list_invoice_ids_and_open_count(
        stripe_client,
        before.customer_id,
        connect_opts,
    )
    new_ids = set(after_ids) - before.invoice_ids
    assert len(new_ids) == 1, (
        f"Expected exactly one new invoice for customer "
        f"{before.customer_id}, got {sorted(new_ids)}"
    )
    new_invoice_id = next(iter(new_ids))
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        new_invoice_id,
        options=connect_opts,
    )

    invoice_sub = _invoice_subscription_id(invoice)
    assert invoice_sub == subscription_id, (
        f"New invoice {invoice.id} belongs to subscription "
        f"{invoice_sub}, expected {subscription_id}"
    )

    assert invoice.amount_due >= min_amount, (
        f"Invoice {invoice.id} amount_due={invoice.amount_due} below min_amount={min_amount}"
    )
    if max_amount is not None:
        assert invoice.amount_due <= max_amount, (
            f"Invoice {invoice.id} amount_due={invoice.amount_due} above max_amount={max_amount}"
        )

    if expect_paid:
        assert invoice.status == "paid", (
            f"Invoice {invoice.id} status={invoice.status}, expected paid"
        )
        assert invoice.amount_paid == invoice.amount_due, (
            f"Invoice {invoice.id} amount_paid={invoice.amount_paid} "
            f"!= amount_due={invoice.amount_due}"
        )

    return invoice


async def fetch_subscription(
    stripe_client: PaymentsStripeClient,
    subscription_id: str,
    connect_opts: stripe.RequestOptions,
    *,
    expand: tuple[str, ...] = SUBSCRIPTION_EXPAND_DEFAULTS,
) -> stripe.Subscription:
    """Retrieve a Stripe subscription with a consistent set of expansions.

    The default expansions make it safe to read ``price``, item-level
    ``discounts``, and subscription-level ``discounts`` without a
    second round trip.
    """
    return await stripe_client.client.v1.subscriptions.retrieve_async(
        subscription_id,
        params={"expand": list(expand)},
        options=connect_opts,
    )


def assert_subscription_item_price(
    sub: stripe.Subscription,
    expected_stripe_price_id: str,
    *,
    index: int = 0,
) -> None:
    """Assert the subscription item at ``index`` uses the expected price."""
    assert len(sub.items.data) > index, (
        f"Subscription {sub.id} has {len(sub.items.data)} items, cannot check index {index}"
    )
    actual = sub.items.data[index].price.id
    assert actual == expected_stripe_price_id, (
        f"Subscription {sub.id} item[{index}] price mismatch: "
        f"expected {expected_stripe_price_id}, got {actual}"
    )


def assert_item_discounts(
    sub: stripe.Subscription,
    expected_coupon_ids: list[str] | set[str] | frozenset[str],
    *,
    index: int = 0,
) -> None:
    """Assert the subscription item at ``index`` has exactly these coupons.

    ``expected_coupon_ids`` is compared as a set, so ordering does not
    matter. An empty collection asserts the item has no discounts.
    """
    assert len(sub.items.data) > index, (
        f"Subscription {sub.id} has {len(sub.items.data)} items, cannot check index {index}"
    )
    item = sub.items.data[index]
    actual = _extract_item_coupon_ids(item)
    expected = set(expected_coupon_ids)
    assert actual == expected, (
        f"Subscription {sub.id} item[{index}] coupon mismatch: "
        f"expected {sorted(expected)}, got {sorted(actual)}"
    )


async def advance_to_next_cycle_and_fetch_invoice(
    stripe_client: PaymentsStripeClient,
    test_clock_id: str,
    advance_to: datetime,
    subscription_id: str,
    before: BillingSnapshot,
    connect_opts: stripe.RequestOptions,
) -> stripe.Invoice:
    """Advance the test clock and return the next invoice for a subscription.

    Flow:
        1. Advance the clock to ``advance_to`` (via
           :func:`tests.helpers.stripe_clock.advance_clock`, which
           already waits for the clock to reach ``ready``).
        2. Poll the customer's invoice list until an invoice that was
           NOT present in ``before.invoice_ids`` and is tied to
           ``subscription_id`` appears.

    Args:
        stripe_client: Configured Stripe client.
        test_clock_id: The test clock to advance.
        advance_to: Target time (UTC).
        subscription_id: Subscription whose next invoice we want.
        before: Snapshot taken before the mid-cycle change.
        connect_opts: Stripe Connect request options.

    Returns:
        The newly generated invoice.

    Raises:
        TimeoutError: If no new invoice appears within the poll budget.
    """
    await advance_clock(
        stripe_client,
        test_clock_id,
        advance_to,
        connect_opts,
    )

    elapsed = 0.0
    while elapsed < INVOICE_POLL_MAX_WAIT_S:
        invoices = await stripe_client.client.v1.invoices.list_async(
            params={
                "customer": before.customer_id,
                "limit": INVOICE_LIST_LIMIT,
            },
            options=connect_opts,
        )
        for inv in invoices.data:
            if inv.id in before.invoice_ids:
                continue
            if _invoice_subscription_id(inv) == subscription_id:
                return inv
        await asyncio.sleep(INVOICE_POLL_INTERVAL_S)
        elapsed += INVOICE_POLL_INTERVAL_S

    raise TimeoutError(
        f"No new invoice appeared for subscription {subscription_id} "
        f"within {INVOICE_POLL_MAX_WAIT_S}s after advancing test clock "
        f"{test_clock_id}"
    )


def assert_invoice_matches(
    invoice: stripe.Invoice,
    *,
    amount_due: int | None = None,
    subtotal: int | None = None,
    discount_total: int | None = None,
    line_price_ids: list[str] | None = None,
) -> None:
    """Assert an invoice's totals and line items match expectations.

    Any argument left as ``None`` is skipped. ``discount_total`` is
    compared against the sum of ``invoice.total_discount_amounts``.
    ``line_price_ids`` compares positionally — use ``None`` in the
    list for any line you do not want to check.
    """
    if amount_due is not None:
        assert invoice.amount_due == amount_due, (
            f"Invoice {invoice.id} amount_due mismatch: "
            f"expected {amount_due}, got {invoice.amount_due}"
        )
    if subtotal is not None:
        assert invoice.subtotal == subtotal, (
            f"Invoice {invoice.id} subtotal mismatch: expected {subtotal}, got {invoice.subtotal}"
        )
    if discount_total is not None:
        actual_total = sum(
            (d.amount for d in (invoice.total_discount_amounts or [])),
            start=0,
        )
        assert actual_total == discount_total, (
            f"Invoice {invoice.id} total discount mismatch: "
            f"expected {discount_total}, got {actual_total}"
        )
    if line_price_ids is not None:
        actual = [line.price.id if line.price is not None else None for line in invoice.lines.data]
        assert actual == line_price_ids, (
            f"Invoice {invoice.id} line price ids mismatch: "
            f"expected {line_price_ids}, got {actual}"
        )


# ── Private ────────────────────────────────────────────────────


async def _list_invoice_ids_and_open_count(
    stripe_client: PaymentsStripeClient,
    customer_id: str,
    connect_opts: stripe.RequestOptions,
) -> tuple[list[str], int]:
    """List invoice IDs for a customer and count how many are ``open``."""
    invoices = await stripe_client.client.v1.invoices.list_async(
        params={"customer": customer_id, "limit": INVOICE_LIST_LIMIT},
        options=connect_opts,
    )
    ids = [inv.id for inv in invoices.data]
    open_count = sum(1 for inv in invoices.data if inv.status == "open")
    return ids, open_count


def _invoice_subscription_id(invoice: stripe.Invoice) -> str | None:
    """Return the subscription id tied to an invoice, or None.

    Newer Stripe API versions moved ``invoice.subscription`` onto
    ``invoice.parent.subscription_details.subscription``. Read both
    shapes so tests keep working across API versions.
    """
    # Legacy shape — still populated on some accounts.
    sub = getattr(invoice, "subscription", None)
    if sub is not None:
        if isinstance(sub, str):
            return sub
        maybe_id = getattr(sub, "id", None)
        if maybe_id:
            return maybe_id

    # Modern shape: invoice.parent.subscription_details.subscription.
    parent = getattr(invoice, "parent", None)
    if parent is None:
        return None
    details = _get_attr_or_key(parent, "subscription_details")
    if details is None:
        return None
    sub_ref = _get_attr_or_key(details, "subscription")
    if sub_ref is None:
        return None
    if isinstance(sub_ref, str):
        return sub_ref
    return _get_attr_or_key(sub_ref, "id")  # type: ignore[return-value]


def _extract_item_coupon_ids(item: stripe.SubscriptionItem) -> set[str]:
    """Pull coupon ids off a subscription item's ``discounts`` field.

    Item discounts come back in several shapes depending on how
    the caller expanded the subscription:

        * a plain coupon id string
        * an expanded ``Discount`` object with ``coupon`` directly
        * a dict with ``coupon`` directly
        * a dict with ``source.coupon`` nested underneath
          (Stripe's expanded per-item discount shape)

    Handle all four so tests can use whichever expansion is
    convenient without forking the walking logic.
    """
    discounts = getattr(item, "discounts", None) or []
    # On StripeObjects the list may be an iterable of StripeObjects; on
    # ``to_dict()`` output it is a list of dicts. Both work here.
    coupon_ids: set[str] = set()
    for d in discounts:
        coupon_id = _coerce_coupon_id(d)
        if coupon_id is not None:
            coupon_ids.add(coupon_id)
    return coupon_ids


def _coerce_coupon_id(discount: object) -> str | None:
    """Resolve an item discount entry to a coupon id, if any."""
    if isinstance(discount, str):
        return discount

    # Unwrap ``source.coupon`` first — that's the expanded shape used
    # by ``params={"expand": ["items.data.discounts.coupon"]}``.
    source = _get_attr_or_key(discount, "source")
    if source is not None:
        coupon = _get_attr_or_key(source, "coupon")
        if coupon is not None:
            return _coupon_to_id(coupon)

    coupon = _get_attr_or_key(discount, "coupon")
    if coupon is not None:
        return _coupon_to_id(coupon)
    return None


def _get_attr_or_key(obj: object, name: str) -> object | None:
    """Read ``name`` off an object (attribute) or a dict (key)."""
    if isinstance(obj, dict):
        return obj.get(name)
    return getattr(obj, name, None)


def _coupon_to_id(coupon: object) -> str | None:
    """Reduce a coupon field to its id, regardless of expansion shape."""
    if coupon is None:
        return None
    if isinstance(coupon, str):
        return coupon
    if isinstance(coupon, dict):
        return coupon.get("id")
    return getattr(coupon, "id", None)
