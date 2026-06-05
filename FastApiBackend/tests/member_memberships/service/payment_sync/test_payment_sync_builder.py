"""Unit tests for the sync-time per-line discount aggregation.

Pure logic, no DB or Stripe. Exercises ``plan_line_discounts`` (the function
that replaced ``aggregate_plan_discounts`` when discounts became frozen
snapshots): for each consolidated subscription line it groups the line's
snapshots, drops past-end_date and consumed ``once`` rows, and aggregates the
survivors per mode — ``percent ÷ quantity`` for percentages, summed dollars for
fixed — keeping ``once`` and ``ongoing`` separate.
"""

from datetime import date
from uuid import UUID, uuid4

from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    AppliedDiscountSnapshot,
    IntervalBucket,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    plan_line_discounts,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
)

TODAY = date(2026, 6, 4)


def _snapshot(
    *,
    stripe_item_id: str = "si_test",
    discount_mode: DiscountMode = DiscountMode.ongoing,
    percentage_off: float | None = None,
    dollar_off: int | None = None,
    end_date: date | None = None,
    stripe_coupon_id: str | None = None,
    applied_discount_id: UUID | None = None,
) -> AppliedDiscountSnapshot:
    return AppliedDiscountSnapshot(
        applied_discount_id=applied_discount_id or uuid4(),
        item_id=uuid4(),
        member_id=uuid4(),
        plan_id=uuid4(),
        stripe_item_id=stripe_item_id,
        discount_mode=discount_mode,
        percentage_off=percentage_off,
        dollar_off=dollar_off,
        end_date=end_date,
        stripe_coupon_id=stripe_coupon_id,
    )


def _bucket(stripe_item_id: str | None, quantity: int) -> IntervalBucket:
    return IntervalBucket(
        interval=DurationUnit.month,
        items=[
            PaymentsSubscriptionDesiredItem(
                stripe_price_id="price_test",
                stripe_item_id=stripe_item_id,
                prorate=False,
                quantity=quantity,
            )
        ],
        existing_sub_id="sub_test",
        total_price=0,
    )


# ── Per-line percent ÷ quantity ─────────────────────────────────────


def test_percent_divided_by_line_quantity() -> None:
    """A 10%-off snapshot on a quantity-2 line becomes 5% on the line."""
    bucket = _bucket("si_test", quantity=2)
    snap = _snapshot(percentage_off=10.0)

    plans = plan_line_discounts(bucket, [snap], set(), TODAY)

    assert len(plans) == 1
    values = plans[0].values
    assert len(values) == 1
    assert values[0].percentage_off == 5.0
    assert values[0].dollar_off is None
    assert values[0].contributing_ids == [snap.applied_discount_id]


def test_percents_summed_then_divided() -> None:
    """Two percent snapshots sum per-unit then divide by quantity."""
    bucket = _bucket("si_test", quantity=2)
    snaps = [
        _snapshot(percentage_off=10.0),
        _snapshot(percentage_off=30.0),
    ]

    plans = plan_line_discounts(bucket, snaps, set(), TODAY)

    # (10 + 30) / 2 = 20%.
    assert plans[0].values[0].percentage_off == 20.0


def test_dollars_summed_not_divided() -> None:
    """Fixed-dollar snapshots are summed, never divided by quantity."""
    bucket = _bucket("si_test", quantity=3)
    snaps = [
        _snapshot(dollar_off=500),
        _snapshot(dollar_off=250),
    ]

    plans = plan_line_discounts(bucket, snaps, set(), TODAY)

    assert plans[0].values[0].dollar_off == 750
    assert plans[0].values[0].percentage_off is None


def test_quantity_zero_treated_as_one() -> None:
    """A degenerate quantity-0 line divides by 1, not by 0."""
    bucket = _bucket("si_test", quantity=0)
    snap = _snapshot(percentage_off=10.0)

    plans = plan_line_discounts(bucket, [snap], set(), TODAY)

    assert plans[0].values[0].percentage_off == 10.0


# ── once / ongoing never mix ────────────────────────────────────────


def test_once_and_ongoing_kept_separate() -> None:
    """A ``once`` and an ``ongoing`` percent produce two distinct values."""
    bucket = _bucket("si_test", quantity=1)
    snaps = [
        _snapshot(discount_mode=DiscountMode.once, percentage_off=10.0),
        _snapshot(discount_mode=DiscountMode.ongoing, percentage_off=20.0),
    ]

    plans = plan_line_discounts(bucket, snaps, set(), TODAY)

    values = plans[0].values
    by_mode = {v.discount_mode: v.percentage_off for v in values}
    assert by_mode == {
        DiscountMode.once: 10.0,
        DiscountMode.ongoing: 20.0,
    }


# ── end_date exclusion ──────────────────────────────────────────────


def test_past_end_date_excluded() -> None:
    """A snapshot whose end_date has passed is dropped from the line."""
    bucket = _bucket("si_test", quantity=1)
    expired = _snapshot(
        percentage_off=10.0,
        end_date=date(2026, 6, 1),  # before TODAY
    )

    plans = plan_line_discounts(bucket, [expired], set(), TODAY)

    assert plans[0].values == []


def test_end_date_today_is_excluded_exclusive() -> None:
    """end_date == today is past (the cutoff is exclusive on the day)."""
    bucket = _bucket("si_test", quantity=1)
    snap = _snapshot(percentage_off=10.0, end_date=TODAY)

    plans = plan_line_discounts(bucket, [snap], set(), TODAY)

    assert plans[0].values == []


def test_future_end_date_still_applies() -> None:
    """A snapshot whose end_date is in the future still contributes."""
    bucket = _bucket("si_test", quantity=1)
    snap = _snapshot(percentage_off=10.0, end_date=date(2026, 7, 1))

    plans = plan_line_discounts(bucket, [snap], set(), TODAY)

    assert plans[0].values[0].percentage_off == 10.0


# ── once consumption gate ───────────────────────────────────────────


def test_once_pending_with_no_coupon_yet_still_applies() -> None:
    """A just-applied ``once`` (null coupon) is pending — it contributes.

    Absence from the live subscription does NOT mean consumed when the
    snapshot has never been attached (stripe_coupon_id is null).
    """
    bucket = _bucket("si_test", quantity=1)
    snap = _snapshot(
        discount_mode=DiscountMode.once,
        percentage_off=10.0,
        stripe_coupon_id=None,
    )

    plans = plan_line_discounts(bucket, [snap], current_coupon_ids=set(), today=TODAY)

    assert plans[0].values[0].percentage_off == 10.0
    assert plans[0].consumed_ids == []


def test_once_still_present_on_sub_is_pending() -> None:
    """A ``once`` whose coupon is still on the sub is pending (re-divides)."""
    bucket = _bucket("si_test", quantity=2)
    snap = _snapshot(
        discount_mode=DiscountMode.once,
        percentage_off=10.0,
        stripe_coupon_id="pct_1000_once",
    )

    plans = plan_line_discounts(
        bucket,
        [snap],
        current_coupon_ids={"pct_1000_once"},
        today=TODAY,
    )

    # Still pending, and re-divided by the (now larger) quantity.
    assert plans[0].values[0].percentage_off == 5.0
    assert plans[0].consumed_ids == []


def test_once_absent_from_sub_is_consumed() -> None:
    """A ``once`` whose coupon vanished from the sub is consumed.

    It is excluded from the line's values and surfaced in consumed_ids so
    the sync can stamp its end_date.
    """
    bucket = _bucket("si_test", quantity=1)
    snap = _snapshot(
        discount_mode=DiscountMode.once,
        percentage_off=10.0,
        stripe_coupon_id="pct_1000_once",
    )

    plans = plan_line_discounts(
        bucket,
        [snap],
        current_coupon_ids=set(),  # coupon no longer present -> invoiced
        today=TODAY,
    )

    assert plans[0].values == []
    assert plans[0].consumed_ids == [snap.applied_discount_id]


def test_consumed_once_does_not_block_ongoing_on_same_line() -> None:
    """A consumed ``once`` is removed but the line's ``ongoing`` survives."""
    bucket = _bucket("si_test", quantity=1)
    once = _snapshot(
        discount_mode=DiscountMode.once,
        percentage_off=10.0,
        stripe_coupon_id="pct_1000_once",
    )
    ongoing = _snapshot(
        discount_mode=DiscountMode.ongoing,
        dollar_off=500,
        stripe_coupon_id="amt_500_ongoing",
    )

    plans = plan_line_discounts(
        bucket,
        [once, ongoing],
        current_coupon_ids={"amt_500_ongoing"},  # once's coupon absent
        today=TODAY,
    )

    assert plans[0].consumed_ids == [once.applied_discount_id]
    assert len(plans[0].values) == 1
    assert plans[0].values[0].dollar_off == 500
    assert plans[0].values[0].discount_mode == DiscountMode.ongoing


# ── line selection ──────────────────────────────────────────────────


def test_line_with_no_stripe_item_id_is_skipped() -> None:
    """A brand-new line (no stripe_item_id yet) gets no plan this sync."""
    bucket = _bucket(None, quantity=1)
    snap = _snapshot(stripe_item_id="si_other", percentage_off=10.0)

    plans = plan_line_discounts(bucket, [snap], set(), TODAY)

    assert plans == []


def test_line_with_no_snapshots_is_skipped() -> None:
    """A line carrying no snapshots produces no plan entry."""
    bucket = _bucket("si_test", quantity=1)

    plans = plan_line_discounts(bucket, [], set(), TODAY)

    assert plans == []


def test_snapshots_routed_to_their_own_line() -> None:
    """Snapshots are grouped by stripe_item_id onto the matching line."""
    bucket = IntervalBucket(
        interval=DurationUnit.month,
        items=[
            PaymentsSubscriptionDesiredItem(
                stripe_price_id="price_a",
                stripe_item_id="si_a",
                prorate=False,
                quantity=1,
            ),
            PaymentsSubscriptionDesiredItem(
                stripe_price_id="price_b",
                stripe_item_id="si_b",
                prorate=False,
                quantity=1,
            ),
        ],
        existing_sub_id="sub_test",
    )
    snaps = [
        _snapshot(stripe_item_id="si_a", percentage_off=10.0),
        _snapshot(stripe_item_id="si_b", dollar_off=500),
    ]

    plans = plan_line_discounts(bucket, snaps, set(), TODAY)

    by_item = {p.stripe_item_id: p for p in plans}
    assert by_item["si_a"].values[0].percentage_off == 10.0
    assert by_item["si_b"].values[0].dollar_off == 500
