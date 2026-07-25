"""Integration: a GENUINE card decline in the start flow returns the client's
decline contract (a per-item ``failed`` result → the router's 207), NOT a 500.

The regression these lock in: a real bank decline at the card-touching steps of
``MemberMembershipsStart.start`` must surface as DATA (a ``failed`` result item
the kiosk/CRM already routes to its "try another card" flow), never as a raised
exception the router turns into an opaque 500 "something went wrong on our side".

Two decline points are covered here (the recurring first-invoice decline already
has coverage in ``test_start_family.py`` via ``_swap_to_failing_card``):

  * ``_set_default_card`` — the recurring cart's card is promoted to the payer's
    default FIRST, before any row is inserted. ``tok_chargeDeclined`` declines
    even on attach, so this exercises the pre-insert decline: no rows exist yet,
    so the response is built from the REQUESTED memberships (all ``failed``).
  * the one-time invoice — a one-off card that declines at pay time.

Plus the guard rails the fix must not break:

  * a NON-card Stripe failure at the same step STILL raises (→ 500) — a system
    failure must never masquerade as a decline;
  * a decline does not corrupt idempotency: retrying the SAME idempotency key
    with a good card succeeds and bills exactly once (one row, one subscription).

Every test cleans up exactly what it creates via ``created`` + an explicit
``delete_member_data`` in a ``finally``. Test payment methods are never cleaned
up (Stripe has no PM delete for test cards; they are inert once orphaned).
"""

from uuid import uuid4

import pytest
import stripe
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartPayment,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import get_profile_stripe_ids


async def _count_membership_rows(db_pool, member_id) -> int:
    """Count ALL membership rows (any status) for a member — the
    nothing-was-written / cleaned-up assertion."""
    sql = (
        "SELECT count(*) AS n FROM member_memberships_unfiltered "
        "WHERE member_id = :member_id"
    )
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql), {"member_id": str(member_id)}
        )
        return int(result.mappings().one()["n"])


async def _make_pm(stripe_client, connect_opts, token: str) -> str:
    """Create a test payment method from a Stripe test token on the connected
    account. (Test PMs are inert once orphaned; nothing to clean up.)"""
    pm = await stripe_client.client.v1.payment_methods.create_async(
        params={"type": "card", "card": {"token": token}},
        options=connect_opts,
    )
    return pm.id


# ── set_default_card decline (recurring cart, BEFORE any insert) ──────


@pytest.mark.timeout(180)
async def test_set_default_card_decline_returns_failed_not_500(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A recurring cart whose card declines while being saved as the default
    returns a ``failed`` breakdown, not a 500.

    ``tok_chargeDeclined`` declines on attach, so the decline lands inside
    ``_set_default_card`` — BEFORE ``_insert_all``. The fix builds the failed
    breakdown from the REQUESTED memberships (nothing was inserted or charged):
      * ``start`` RETURNS (does not raise) — before the fix it raised a
        ``stripe.CardError`` the router turned into a 500;
      * the lone result is ``failed`` with a "declined" reason;
      * ``charge_count == 0`` (nothing was ever charged);
      * NO membership rows were written and NO subscription exists.
    """
    member = await created.member(
        gym_id, first_name="SetDefault", last_name="Decline",
    )
    plan = await created.plan(
        gym_id, plan_name="Decline Monthly", price_cents=5000,
    )
    declining_pm = await _make_pm(
        stripe_client, connect_opts, "tok_chargeDeclined"
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                payment=MemberMembershipsStartPayment(
                    payment_method_id=declining_pm,
                    set_default=True,
                ),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id, price_id=plan.price_id,
                    ),
                ],
            )
        )

        # The decline is a RESULT, not a raise (the whole point of the fix).
        assert response.charge_count == 0
        assert response.multiple_charges is False
        assert len(response.results) == 1
        result = response.results[0]
        assert result.status.value == "failed"
        assert result.item_id is None
        assert result.error is not None
        assert "declined" in result.error.lower()

        # Nothing was inserted (the decline happened before _insert_all) and no
        # subscription / charge exists.
        assert await _count_membership_rows(db_pool, member.member_id) == 0
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is None
        subs = await stripe_client.client.v1.subscriptions.list_async(
            params={
                "customer": member.stripe_customer_id,
                "status": "all",
                "limit": 10,
            },
            options=connect_opts,
        )
        assert subs.data == []
    finally:
        await delete_member_data(db_pool, member.member_id)


@pytest.mark.timeout(180)
async def test_set_default_card_non_card_error_still_raises(
    memberships_service,
    gym_id,
    db_pool,
    created,
):
    """A NON-card Stripe failure at set-default STILL raises (→ 500).

    An unknown payment-method id makes the attach raise
    ``stripe.InvalidRequestError`` — a system/bad-input failure, NOT a decline.
    The fix catches ONLY ``stripe.CardError`` there, so this propagates out of
    ``start`` (the router maps it to a non-retryable 500). The rule the test
    guards: a system failure must never be swallowed into a "declined" result.
    """
    member = await created.member(
        gym_id, first_name="SetDefault", last_name="Boom",
    )
    plan = await created.plan(
        gym_id, plan_name="Boom Monthly", price_cents=5000,
    )

    try:
        with pytest.raises(stripe.StripeError) as exc_info:
            await memberships_service.start(
                MemberMembershipsStartRequest(
                    payer_member_id=member.member_id,
                    gym_id=gym_id,
                    idempotency_key=uuid4(),
                    proration_behavior=ProrationBehavior.prorate_to_anchor,
                    paid_with_cash=False,
                    payment=MemberMembershipsStartPayment(
                        payment_method_id="pm_nonexistent_000000000000",
                        set_default=True,
                    ),
                    memberships=[
                        MemberMembershipsStartItem(
                            member_id=member.member_id,
                            price_id=plan.price_id,
                        ),
                    ],
                )
            )
        # A non-card error is NOT a decline — it must not be caught as one.
        assert not isinstance(exc_info.value, stripe.CardError)
        # The abort happened before any insert.
        assert await _count_membership_rows(db_pool, member.member_id) == 0
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── one-time invoice decline (one-off card) ──────────────────────────


@pytest.mark.timeout(240)
async def test_one_time_charge_decline_returns_failed(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A one-time cart whose one-off card declines at pay time → ``failed``.

    A purely one-time cart sends the card as a one-off (attach → pay → detach,
    ``set_default=False``). ``tok_chargeCustomerFail`` attaches cleanly but the
    ``invoices.pay`` declines, so the decline lands in the one-time charge step
    AFTER the pending row was inserted:
      * ``start`` RETURNS (does not raise);
      * the result is ``failed`` with a "declined" reason;
      * the un-billed pending row was cleaned up (no rows remain);
      * no charge succeeded.
    """
    member = await created.member(
        gym_id, first_name="OneTime", last_name="Decline",
    )
    plan = await created.plan(
        gym_id,
        plan_type="one_time",
        plan_name="Decline Pass",
        price_cents=2500,
        duration_amount=1,
        duration_unit="month",
    )
    one_off_pm = await _make_pm(
        stripe_client, connect_opts, "tok_chargeCustomerFail"
    )

    try:
        response = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                paid_with_cash=False,
                payment=MemberMembershipsStartPayment(
                    payment_method_id=one_off_pm,
                    set_default=False,
                ),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=member.member_id, price_id=plan.price_id,
                    ),
                ],
            )
        )

        assert response.charge_count == 1
        assert len(response.results) == 1
        result = response.results[0]
        assert result.status.value == "failed"
        assert result.error is not None
        assert "declined" in result.error.lower()

        # The un-billed pending one-time row was cleaned up.
        assert await _count_membership_rows(db_pool, member.member_id) == 0

        # No charge succeeded against the declining card.
        invoices = await stripe_client.client.v1.invoices.list_async(
            params={"customer": member.stripe_customer_id, "limit": 10},
            options=connect_opts,
        )
        assert all(inv.amount_paid == 0 for inv in invoices.data), (
            "no charge should have succeeded against a declining card"
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


# ── idempotency: a decline does not block a same-key retry ──────────


@pytest.mark.timeout(300)
async def test_decline_then_same_key_retry_succeeds_once(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A set-default decline leaves idempotency clean: the SAME key + a good
    card succeeds and bills EXACTLY once.

    The pre-insert decline writes no rows, so re-firing the identical request
    (same ``idempotency_key``) with a working card is not a replay — it inserts,
    charges once, and lands ``created``. Proves the decline corrupted neither
    the per-row idempotency keys (no false 409) nor produced a double-charge
    (exactly one membership row and one subscription).
    """
    member = await created.member(
        gym_id, first_name="Retry", last_name="AfterDecline",
    )
    plan = await created.plan(
        gym_id, plan_name="Retry Monthly", price_cents=5000,
    )
    declining_pm = await _make_pm(
        stripe_client, connect_opts, "tok_chargeDeclined"
    )
    good_pm = await created.payment_method()

    key = uuid4()
    memberships = [
        MemberMembershipsStartItem(
            member_id=member.member_id, price_id=plan.price_id,
        ),
    ]

    try:
        # Attempt 1: declining card at set-default → all failed, nothing written.
        declined = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=key,
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                payment=MemberMembershipsStartPayment(
                    payment_method_id=declining_pm, set_default=True,
                ),
                memberships=memberships,
            )
        )
        assert declined.results[0].status.value == "failed"
        assert await _count_membership_rows(db_pool, member.member_id) == 0

        # Attempt 2: SAME idempotency key, a GOOD card → succeeds.
        succeeded = await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=member.member_id,
                gym_id=gym_id,
                idempotency_key=key,
                proration_behavior=ProrationBehavior.prorate_to_anchor,
                paid_with_cash=False,
                payment=MemberMembershipsStartPayment(
                    payment_method_id=good_pm, set_default=True,
                ),
                memberships=memberships,
            )
        )
        assert succeeded.results[0].status.value == "created", (
            f"same-key retry with a good card must succeed; "
            f"error={succeeded.results[0].error}"
        )

        # Billed EXACTLY once: one membership row, one subscription.
        assert await _count_membership_rows(db_pool, member.member_id) == 1
        profile = await get_profile_stripe_ids(
            db_pool, member.member_id, gym_id
        )
        assert profile.stripe_sub_id_month is not None
        subs = await stripe_client.client.v1.subscriptions.list_async(
            params={
                "customer": member.stripe_customer_id,
                "status": "all",
                "limit": 10,
            },
            options=connect_opts,
        )
        assert len(subs.data) == 1
    finally:
        await delete_member_data(db_pool, member.member_id)
