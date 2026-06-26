"""Integration tests for the ``invoice.paid`` handler.

Verifies that a successful subscription renewal:
  - upserts a ``member_invoices`` row to ``status='paid'``
  - inserts the itemized ``member_invoice_line_items``
  - updates ``member_memberships.last_paid_date`` / ``next_due_date``

The succeeded ``member_charges`` row is NOT written here — a paid invoice's
payment(s) arrive on the separate ``invoice_payment.paid`` event, covered by
``test_invoice_payment_paid.py``.
"""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.shared.gym_timezone import get_gym_timezone, stripe_ts_to_gym_date
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import create_member
from tests.stripe_webhooks.event_builders import make_invoice_paid_event


async def _fetch_invoice(db_pool, stripe_invoice_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT status, total_amount, currency, "
                "paid_by_member_id, paid_for "
                "FROM member_invoices "
                "WHERE stripe_invoice_id = :id"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _fetch_membership_dates(db_pool, item_id) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT last_paid_date, next_due_date "
                "FROM member_memberships_unfiltered "
                "WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _fetch_line_item(db_pool, line_item_id: str) -> dict | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT item_type, item_id, amount, name "
                "FROM member_invoice_line_items "
                "WHERE line_item_id = :id"
            ),
            {"id": line_item_id},
        )
        row = result.mappings().fetchone()
    return dict(row) if row else None


async def _charges_for_invoice(db_pool, stripe_invoice_id: str) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM member_charges "
                "WHERE invoice_id IN ("
                "  SELECT invoice_id FROM member_invoices "
                "  WHERE stripe_invoice_id = :id"
                ")"
            ),
            {"id": stripe_invoice_id},
        )
        row = result.mappings().fetchone()
    return int(row["n"])


async def test_invoice_paid_writes_invoice_and_dates(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    paid_at = int(datetime(2026, 4, 1, 12, 0, tzinfo=UTC).timestamp())
    period_end = int(datetime(2026, 5, 1, 12, 0, tzinfo=UTC).timestamp())
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=5000,
        paid_at=paid_at,
        period_end=period_end,
    )

    await stripe_webhooks_service.handle_event(event)

    # Invoice upserted to paid.
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "paid"
    assert invoice["total_amount"] == 5000
    assert invoice["currency"] == "usd"
    # Subscription invoice: payer = the membership's paid_by_member_id (the
    # fixture self-pays, so == member_id) and paid_for lists the owner.
    assert str(invoice["paid_by_member_id"]) == str(webhook_fixture.member_id)
    assert [str(m) for m in invoice["paid_for"]] == [str(webhook_fixture.member_id)]

    # The charge is the invoice_payment.paid handler's job, not this one.
    assert await _charges_for_invoice(db_pool, event["data"]["object"]["id"]) == 0

    # Membership dates advanced.
    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates is not None
    assert dates["last_paid_date"] == datetime.fromtimestamp(paid_at, tz=UTC).date()
    assert dates["next_due_date"] == datetime.fromtimestamp(period_end, tz=UTC).date()


async def test_invoice_paid_raises_when_subscription_items_unresolved(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,  # ensure the gym exists even though we don't match it
):
    """Unresolved subscription items raise so a background retry is scheduled."""
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=["si_test_does_not_exist"],
        amount_paid=1000,
    )

    with pytest.raises(SubscriptionItemPendingError):
        await stripe_webhooks_service.handle_event(event)

    # No invoice row created (transaction rolled back).
    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is None

    # Webhook event NOT recorded (transaction rolled back).
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT COUNT(*) AS n FROM stripe_webhook_events WHERE event_id = :id"),
            {"id": event["id"]},
        )
        row = result.mappings().fetchone()
    assert int(row["n"]) == 0


async def test_invoice_paid_zero_amount_records_invoice(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    webhook_fixture,
):
    """A $0 invoice (100%-off trial) still records the invoice + advances dates.

    No ``invoice_payment.paid`` fires for a $0 invoice (no money moves), so
    there is never a charge row for it — exactly right.
    """
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=0,
    )

    await stripe_webhooks_service.handle_event(event)

    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "paid"
    assert invoice["total_amount"] == 0

    assert await _charges_for_invoice(db_pool, event["data"]["object"]["id"]) == 0

    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates["last_paid_date"] is not None
    assert dates["next_due_date"] is not None


async def test_invoice_paid_is_idempotent_on_repeat(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        amount_paid=5000,
    )

    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)
    await stripe_webhooks_service.handle_event(event)

    # Exactly one invoice and one event row, regardless of replays. No charge
    # (invoice.paid does not record charges).
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT "
                " (SELECT COUNT(*) FROM member_invoices WHERE gym_id = :g) AS inv,"
                " (SELECT COUNT(*) FROM member_charges WHERE gym_id = :g) AS chg,"
                " (SELECT COUNT(*) FROM stripe_webhook_events WHERE gym_id = :g) AS evt"
            ),
            {"g": str(gym_id)},
        )
        row = result.mappings().fetchone()
    assert int(row["inv"]) == 1
    assert int(row["chg"]) == 0
    assert int(row["evt"]) == 1


async def test_invoice_paid_advances_two_different_period_ends(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """Two events with different period_ends should update the
    membership to the latest value each time."""
    first_end = int(datetime(2026, 6, 1, tzinfo=UTC).timestamp())
    second_end = int(datetime(2026, 7, 1, tzinfo=UTC).timestamp())

    evt_1 = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        period_end=first_end,
    )
    evt_2 = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[webhook_fixture.stripe_item_id],
        period_end=second_end,
    )

    # next_due_date is stored GYM-LOCAL (the handler converts the Stripe
    # period-end timestamp to the gym's timezone), so compare against the
    # gym-local date, not the UTC date — a midnight-UTC timestamp lands on the
    # previous day for a gym west of UTC.
    async with db_pool.session() as session:
        gym_tz = await get_gym_timezone(session, gym_id)

    await stripe_webhooks_service.handle_event(evt_1)
    dates_1 = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates_1["next_due_date"] == stripe_ts_to_gym_date(first_end, gym_tz)

    await stripe_webhooks_service.handle_event(evt_2)
    dates_2 = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates_2["next_due_date"] == stripe_ts_to_gym_date(second_end, gym_tz)

    # Proximity sanity — the delta is roughly a month.
    assert dates_2["next_due_date"] - dates_1["next_due_date"] >= timedelta(days=28)


async def test_invoice_paid_consolidated_item_records_all_co_owners(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    stripe_client,
    connect_opts,
    webhook_fixture,
):
    """A consolidated Stripe item (quantity > 1) is shared by MULTIPLE
    memberships — co-owners billed at one price. ``paid_for`` must list
    EVERY owner, not just the first.

    Regression: the resolver used ``LIMIT 1`` on the stripe-item lookup, so
    a second person on a shared item was silently dropped from paid_for (and
    their payment dates never advanced).
    """
    # A second member with a membership on the SAME stripe_item_id (co-owner),
    # cloning the fixture membership's payer/plan/price.
    co_owner = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Co", last_name="Owner",
    )
    try:
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "INSERT INTO member_memberships_unfiltered ("
                    " member_id, paid_by_member_id, gym_id, plan_id, price_id,"
                    " start_date, stripe_item_id, total_price, "
                    " stripe_sync_status) "
                    "SELECT :member_id, paid_by_member_id, gym_id, plan_id, "
                    " price_id, CURRENT_DATE, stripe_item_id, total_price, "
                    " 'applied' "
                    "FROM member_memberships_unfiltered WHERE item_id = :base"
                ),
                {
                    "member_id": str(co_owner.member_id),
                    "base": str(webhook_fixture.item_id),
                },
            )
            await session.commit()

        event = make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[webhook_fixture.stripe_item_id],
            amount_paid=10000,
        )
        await stripe_webhooks_service.handle_event(event)

        invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
        assert invoice is not None
        paid_for = {str(m) for m in invoice["paid_for"]}
        assert paid_for == {
            str(webhook_fixture.member_id),
            str(co_owner.member_id),
        }, f"paid_for must list BOTH co-owners, got {paid_for}"
    finally:
        await delete_member_data(db_pool, co_owner.member_id)


async def test_invoice_paid_one_time_payment_records_invoice(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """An ad-hoc one-time invoice (no subscription item, carries
    ``crm_one_time_payment`` + ``paid_by_member_id`` + ``paid_for`` in root
    metadata) records the invoice resolved from metadata, WITHOUT touching
    membership dates. Its charge arrives on ``invoice_payment.paid``.

    The payer and beneficiary differ here (a parent paying for a child), so
    this also proves the payer/beneficiary split round-trips: paid_for is a
    JSON-array string in metadata and lands as a JSONB list on the row.
    """
    beneficiary_id = uuid4()
    paid_at = int(datetime(2026, 4, 10, 12, 0, tzinfo=UTC).timestamp())
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[],
        amount_paid=2500,
        paid_at=paid_at,
        metadata={
            "crm_one_time_payment": "true",
            "paid_by_member_id": str(webhook_fixture.member_id),
            "paid_for": json.dumps([str(beneficiary_id)]),
            "gym_id": str(gym_id),
        },
    )

    await stripe_webhooks_service.handle_event(event)

    invoice = await _fetch_invoice(db_pool, event["data"]["object"]["id"])
    assert invoice is not None
    assert invoice["status"] == "paid"
    assert invoice["total_amount"] == 2500
    assert str(invoice["paid_by_member_id"]) == str(webhook_fixture.member_id)
    assert [str(m) for m in invoice["paid_for"]] == [str(beneficiary_id)]

    # The one-time branch must NOT advance membership dates.
    dates = await _fetch_membership_dates(db_pool, webhook_fixture.item_id)
    assert dates is not None
    assert dates["last_paid_date"] is None
    assert dates["next_due_date"] is None


async def test_invoice_paid_one_time_membership_line_carries_item_id(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    stripe_client,
    connect_opts,
    webhook_fixture,
):
    """A one-time membership's invoice line carries its membership item_id.

    Regression: a one-time / trial line has NO ``subscription_item``, so the
    line→membership resolver (which keyed only on ``subscription_item``) left
    ``member_invoice_line_items.item_id`` NULL — the membership card then can't
    find the charge to refund, and Payment History can't match the line to the
    membership. A one-time membership's ``stripe_item_id`` IS the invoice line
    id, so the resolver falls back to the line id. This proves the line lands
    as ``item_type='membership'`` with the right ``item_id``.
    """
    buyer = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="OneTime", last_name="Buyer",
    )
    # A one-time membership stores the invoice LINE id (il_...) as its
    # stripe_item_id — not a si_ subscription item. Clone the fixture's
    # plan/price (the resolver keys on stripe_item_id, never plan_type).
    line_item_id = f"il_onetime_{buyer.member_id.hex[:12]}"
    try:
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "INSERT INTO member_memberships_unfiltered ("
                    " member_id, paid_by_member_id, gym_id, plan_id, price_id,"
                    " start_date, stripe_item_id, total_price, "
                    " stripe_sync_status) "
                    "SELECT :member_id, :member_id, gym_id, plan_id, price_id, "
                    " CURRENT_DATE, :stripe_item_id, total_price, 'applied' "
                    "FROM member_memberships_unfiltered WHERE item_id = :base "
                    "RETURNING item_id"
                ),
                {
                    "member_id": str(buyer.member_id),
                    "stripe_item_id": line_item_id,
                    "base": str(webhook_fixture.item_id),
                },
            )
            ot_item_id = UUID(str(result.mappings().fetchone()["item_id"]))
            await session.commit()

        event = make_invoice_paid_event(
            stripe_account_id=stripe_account_id,
            stripe_item_ids=[],
            one_time_line_ids=[line_item_id],
            amount_paid=2500,
            metadata={
                "crm_one_time_payment": "true",
                "paid_by_member_id": str(buyer.member_id),
                "paid_for": json.dumps([str(buyer.member_id)]),
                "gym_id": str(gym_id),
            },
        )
        await stripe_webhooks_service.handle_event(event)

        # The one-time line resolved to its membership by the line-id fallback.
        line = await _fetch_line_item(db_pool, line_item_id)
        assert line is not None
        assert line["item_type"] == "membership"
        assert str(line["item_id"]) == str(ot_item_id)

        # A one-time invoice still does not advance membership dates.
        dates = await _fetch_membership_dates(db_pool, ot_item_id)
        assert dates is not None
        assert dates["last_paid_date"] is None
        assert dates["next_due_date"] is None
    finally:
        await delete_member_data(db_pool, buyer.member_id)


async def test_invoice_paid_one_time_adhoc_line_stays_custom(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
    webhook_fixture,
):
    """A one-time line matching NO membership stays ``item_type='custom'``.

    The line-id fallback must only stamp a line whose id equals a membership's
    ``stripe_item_id``. A genuine ad-hoc charge-card line (its id matches no
    membership) matches neither ``subscription_item`` nor a membership, so it
    must stay ``custom`` with a NULL ``item_id`` — the fallback must not
    over-claim arbitrary one-time lines.
    """
    line_item_id = "il_adhoc_no_membership"
    event = make_invoice_paid_event(
        stripe_account_id=stripe_account_id,
        stripe_item_ids=[],
        one_time_line_ids=[line_item_id],
        amount_paid=2500,
        metadata={
            "crm_one_time_payment": "true",
            "paid_by_member_id": str(webhook_fixture.member_id),
            "paid_for": json.dumps([str(webhook_fixture.member_id)]),
            "gym_id": str(gym_id),
        },
    )
    await stripe_webhooks_service.handle_event(event)

    line = await _fetch_line_item(db_pool, line_item_id)
    assert line is not None
    assert line["item_type"] == "custom"
    assert line["item_id"] is None
