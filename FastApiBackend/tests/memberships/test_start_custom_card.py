"""Integration: a card entered at checkout, routed through the start op.

Covers the ``MemberMembershipsStartRequest.payment`` field end to end against
the real Stripe test Connect account + shared DB:

- a **one-off** card (``set_default`` False) pays the one-time invoice and is
  detached, leaving the saved default untouched;
- ``set_default`` promotes the card to the customer's default **up-front**
  (the old default is detached), so it bills the one-time invoice AND a
  recurring subscription;
- a card on a request that has a recurring membership is **rejected** unless
  ``set_default`` is set (recurring can only bill the saved default).
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartPayment,
    MemberMembershipsStartRequest,
)


async def _customer_id(db_pool, member_id) -> str:
    sql = "SELECT stripe_customer_id FROM members WHERE member_id = :id"
    async with db_pool.session() as session:
        result = await session.execute(text(sql), {"id": str(member_id)})
        return result.mappings().one()["stripe_customer_id"]


async def _default_pm(stripe_client, customer_id, connect_opts):
    customer = await stripe_client.client.v1.customers.retrieve_async(
        customer_id, options=connect_opts
    )
    settings = customer.invoice_settings
    return settings.default_payment_method if settings else None


async def _membership_row(db_pool, member_id, gym_id) -> dict:
    sql = """
        SELECT item_id, stripe_item_id,
               stripe_one_time_invoice_id,
               stripe_sync_status::text AS status, total_price
        FROM member_memberships_unfiltered
        WHERE member_id = :member_id AND gym_id = :gym_id
        ORDER BY created_at DESC
        LIMIT 1
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"member_id": str(member_id), "gym_id": str(gym_id)},
        )
        return dict(result.mappings().one())


async def _row_count(db_pool, member_id, gym_id) -> int:
    sql = """
        SELECT COUNT(*) AS n FROM member_memberships_unfiltered
        WHERE member_id = :member_id AND gym_id = :gym_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"member_id": str(member_id), "gym_id": str(gym_id)},
        )
        return result.mappings().one()["n"]


def _request(member, gym_id, plan, payment):
    return MemberMembershipsStartRequest(
        payer_member_id=member.member_id,
        gym_id=gym_id,
        idempotency_key=uuid4(),
        payment=payment,
        memberships=[
            MemberMembershipsStartItem(
                member_id=member.member_id,
                price_id=plan.price_id,
            ),
        ],
    )


@pytest.mark.timeout(180)
async def test_one_off_card_pays_and_leaves_default(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """One-off (no set_default): the invoice is paid by the one-off card, the
    saved default is untouched, and the one-off card is detached."""
    default_pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=default_pm)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )
    one_off_pm = await created.payment_method()
    customer_id = await _customer_id(db_pool, member.member_id)
    before = await _default_pm(stripe_client, customer_id, connect_opts)

    await memberships_service.start(
        _request(
            member,
            gym_id,
            plan,
            MemberMembershipsStartPayment(payment_method_id=one_off_pm),
        )
    )

    row = await _membership_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["total_price"] == 5000
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"
    assert invoice.amount_paid == 5000

    # The saved default never moved...
    after = await _default_pm(stripe_client, customer_id, connect_opts)
    assert after == before
    # ...and the one-off card was detached.
    one_off = await stripe_client.client.v1.payment_methods.retrieve_async(
        one_off_pm, options=connect_opts
    )
    assert one_off.customer is None


@pytest.mark.timeout(180)
async def test_set_default_on_one_time_promotes_card(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """set_default on a one-time cart promotes the new card to the customer
    default (old default detached) and pays the invoice with it."""
    old_pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=old_pm)
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        price_cents=5000,
        duration_amount=1,
        duration_unit="month",
    )
    new_pm = await created.payment_method()
    customer_id = await _customer_id(db_pool, member.member_id)
    before = await _default_pm(stripe_client, customer_id, connect_opts)

    await memberships_service.start(
        _request(
            member,
            gym_id,
            plan,
            MemberMembershipsStartPayment(
                payment_method_id=new_pm,
                set_default=True,
            ),
        )
    )

    row = await _membership_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    invoice = await stripe_client.client.v1.invoices.retrieve_async(
        row["stripe_one_time_invoice_id"], options=connect_opts
    )
    assert invoice.status == "paid"

    # The new card is now the saved default...
    after = await _default_pm(stripe_client, customer_id, connect_opts)
    assert after == new_pm
    assert after != before
    # ...and the previous default was detached.
    if before:
        old = await stripe_client.client.v1.payment_methods.retrieve_async(
            before, options=connect_opts
        )
        assert old.customer is None


@pytest.mark.timeout(180)
async def test_recurring_card_requires_set_default(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """A card on a request with a recurring membership is rejected unless
    set_default is set — and nothing is written."""
    default_pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=default_pm)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        price_cents=4000,
        duration_amount=1,
        duration_unit="month",
    )
    new_pm = await created.payment_method()

    with pytest.raises(ValueError, match="set_default"):
        await memberships_service.start(
            _request(
                member,
                gym_id,
                plan,
                MemberMembershipsStartPayment(payment_method_id=new_pm),
            )
        )

    assert await _row_count(db_pool, member.member_id, gym_id) == 0


@pytest.mark.timeout(240)
async def test_recurring_with_set_default_bills_new_card(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """set_default + a recurring membership: the new card becomes the default
    up-front, so the recurring subscription bills it; the old default is
    detached."""
    old_pm = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=old_pm)
    plan = await created.plan(
        gym_id,
        plan_type="recurring",
        price_cents=4000,
        duration_amount=1,
        duration_unit="month",
    )
    new_pm = await created.payment_method()
    customer_id = await _customer_id(db_pool, member.member_id)

    await memberships_service.start(
        _request(
            member,
            gym_id,
            plan,
            MemberMembershipsStartPayment(
                payment_method_id=new_pm,
                set_default=True,
            ),
        )
    )

    # The recurring membership converged (a subscription item was stamped)...
    row = await _membership_row(db_pool, member.member_id, gym_id)
    assert row["status"] == "applied"
    assert row["stripe_item_id"] is not None
    # ...and the new card is the saved default the subscription bills.
    after = await _default_pm(stripe_client, customer_id, connect_opts)
    assert after == new_pm
    old = await stripe_client.client.v1.payment_methods.retrieve_async(
        old_pm, options=connect_opts
    )
    assert old.customer is None
