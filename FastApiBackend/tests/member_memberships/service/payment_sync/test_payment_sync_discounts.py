"""Unit tests for the sync-time per-line discount aggregation + resolution.

Pure logic, no DB or Stripe. Exercises ``PaymentSyncDiscounts``:

* ``_aggregate_line_values`` — the discount MATH for one consolidated line (a
  price group of memberships). Within a membership multiple percents compound
  **sequentially** (``eff = 1 − Π(1 − pⱼ/100)``); the per-membership effective
  fractions are summed across the line then divided by the line quantity; fixed
  dollars are summed; ``once`` and ``ongoing`` never mix; percent vs dollar carry
  **disjoint** ``contributing_ids``.
* ``resolve`` — orders percent-before-dollar, find-or-creates one coupon per
  value (the Stripe I/O mocked), and records the ``applied_discount_id →
  coupon_id`` links.

The date/end_date cutoff and the ``once``-consumption gate are NOT in this math —
they live in the SQL read and ``PaymentSyncOnceDiscounts`` respectively — so they
are exercised by the integration tests, not here.
"""

from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    AppliedDiscount,
    LineDiscountValue,
)
from src.member_memberships.service.payment_sync.payment_sync_discounts import (
    PaymentSyncDiscounts,
)


def _disc(
    *,
    discount_mode: DiscountMode = DiscountMode.ongoing,
    percentage_off: float | None = None,
    dollar_off: int | None = None,
    applied_discount_id: UUID | None = None,
) -> AppliedDiscount:
    return AppliedDiscount(
        applied_discount_id=applied_discount_id or uuid4(),
        item_id=uuid4(),
        member_id=uuid4(),
        plan_id=uuid4(),
        discount_mode=discount_mode,
        percentage_off=percentage_off,
        dollar_off=dollar_off,
    )


def _membership(discounts: list[AppliedDiscount]) -> ActiveMembershipRow:
    """An active membership on one shared line, carrying its discounts."""
    return ActiveMembershipRow(
        item_id=uuid4(),
        member_id=uuid4(),
        plan_id=uuid4(),
        price_id=uuid4(),
        stripe_price_id="price_shared",
        stripe_item_id="si_shared",
        duration_unit=DurationUnit.month,
        discounts=discounts,
    )


def _aggregate(memberships: list[ActiveMembershipRow]):
    # _aggregate_line_values needs no Stripe; pass None for the discount service.
    return PaymentSyncDiscounts(discount_service=None)._aggregate_line_values(
        memberships
    )


# ── single membership ───────────────────────────────────────────────


def test_single_percent_qty_one() -> None:
    """One 10% membership on a quantity-1 line → 10% on the line."""
    snap = _disc(percentage_off=10.0)
    values = _aggregate([_membership([snap])])

    assert len(values) == 1
    # Float artifact: 1 - (1 - 10/100) = 9.9999…; rounds to 10% / pct_1000.
    assert values[0].percentage_off == pytest.approx(10.0)
    assert values[0].dollar_off is None
    assert values[0].discount_mode == DiscountMode.ongoing
    assert values[0].contributing_ids == [snap.applied_discount_id]


def test_two_percents_on_one_membership_compound_sequentially() -> None:
    """30% then 20% on the SAME membership compound to 44%, not 50%."""
    snaps = [_disc(percentage_off=30.0), _disc(percentage_off=20.0)]
    values = _aggregate([_membership(snaps)])

    # 1 - (1-0.30)(1-0.20) = 0.44 -> 44% on a quantity-1 line.
    assert values[0].percentage_off == pytest.approx(44.0)
    assert set(values[0].contributing_ids) == {
        s.applied_discount_id for s in snaps
    }


def test_hundred_percent_stays_hundred() -> None:
    """A 100% discount stays 100% (the validator allows le=100)."""
    values = _aggregate([_membership([_disc(percentage_off=100.0)])])

    assert values[0].percentage_off == pytest.approx(100.0)


def test_dollars_summed_on_one_membership() -> None:
    """Two fixed-dollar discounts on one membership sum (cents)."""
    snaps = [_disc(dollar_off=1000), _disc(dollar_off=1000)]
    values = _aggregate([_membership(snaps)])

    # $10 + $10 = 2000 cents, never divided.
    assert len(values) == 1
    assert values[0].dollar_off == 2000
    assert values[0].percentage_off is None


# ── across the consolidated line (÷ quantity) ───────────────────────


def test_percent_averaged_across_line_quantity() -> None:
    """One 10% membership on a quantity-2 line → 5% on the line."""
    discounted = _membership([_disc(percentage_off=10.0)])
    plain = _membership([])  # no discount → contributes 0
    values = _aggregate([discounted, plain])

    # (0.10 + 0) / 2 = 0.05 -> 5%.
    assert values[0].percentage_off == pytest.approx(5.0)


def test_mixed_members_effective_fractions_averaged() -> None:
    """Member A (30%+20% → 0.44) and member B (10% → 0.10) over qty 2 → 27%."""
    a = _membership([_disc(percentage_off=30.0), _disc(percentage_off=20.0)])
    b = _membership([_disc(percentage_off=10.0)])
    values = _aggregate([a, b])

    # (0.44 + 0.10) / 2 = 0.27 -> 27%.
    assert values[0].percentage_off == pytest.approx(27.0)


def test_dollars_summed_across_members_not_divided() -> None:
    """Fixed dollars sum across the line's members (no ÷ quantity)."""
    a = _membership([_disc(dollar_off=500)])
    b = _membership([_disc(dollar_off=500)])
    values = _aggregate([a, b])

    assert values[0].dollar_off == 1000


# ── once / ongoing separation ───────────────────────────────────────


def test_once_and_ongoing_kept_separate() -> None:
    """A once and an ongoing percent on one line produce two distinct values."""
    snaps = [
        _disc(discount_mode=DiscountMode.once, percentage_off=10.0),
        _disc(discount_mode=DiscountMode.ongoing, percentage_off=20.0),
    ]
    values = _aggregate([_membership(snaps)])

    by_mode = {v.discount_mode: v.percentage_off for v in values}
    assert by_mode == {
        DiscountMode.once: pytest.approx(10.0),
        DiscountMode.ongoing: pytest.approx(20.0),
    }


# ── percent vs dollar: disjoint contributing_ids ────────────────────


def test_percent_and_dollar_get_disjoint_contributing_ids() -> None:
    """A percent and a dollar of the same mode produce two values whose
    contributing_ids never overlap (each discount is percent XOR dollar)."""
    pct = _disc(percentage_off=10.0)
    amt = _disc(dollar_off=500)
    values = _aggregate([_membership([pct, amt])])

    by_kind = {
        "pct": next(v for v in values if v.percentage_off is not None),
        "amt": next(v for v in values if v.dollar_off is not None),
    }
    assert by_kind["pct"].contributing_ids == [pct.applied_discount_id]
    assert by_kind["amt"].contributing_ids == [amt.applied_discount_id]
    assert not set(by_kind["pct"].contributing_ids) & set(
        by_kind["amt"].contributing_ids
    )


# ── empties ─────────────────────────────────────────────────────────


def test_no_discounts_yields_no_values() -> None:
    assert _aggregate([_membership([])]) == []


def test_empty_line_yields_no_values() -> None:
    """An empty membership list divides by 1 (no ZeroDivisionError) → []."""
    assert _aggregate([]) == []


# ── resolve(): ordering + links (Stripe mocked) ─────────────────────


class _FakeDiscountService:
    """A PaymentsStripeDiscountService double: no coupon exists, create echoes
    back the deterministic id it was handed (no Stripe I/O)."""

    def __init__(self) -> None:
        self.created: list[str] = []

    async def find_discount(self, coupon_id: str, account: str):
        return None

    async def create_discount(self, request, account: str):
        self.created.append(request.coupon_id)
        return SimpleNamespace(stripe_coupon_id=request.coupon_id)


async def test_resolve_orders_percent_before_dollar_and_links() -> None:
    """One line with a percent + a dollar → percent coupon first, then dollar;
    links map each contributing id to its own coupon."""
    pct = _disc(discount_mode=DiscountMode.ongoing, percentage_off=10.0)
    amt = _disc(discount_mode=DiscountMode.ongoing, dollar_off=500)
    price_id = uuid4()
    groups = {price_id: [_membership([pct, amt])]}

    resolved = await PaymentSyncDiscounts(_FakeDiscountService()).resolve(
        groups, "acct_test"
    )

    coupons = [d.coupon for d in resolved.coupons_by_price[price_id]]
    assert coupons == ["pct_1000_ongoing", "amt_500_ongoing"]
    assert resolved.links[amt.applied_discount_id] == "amt_500_ongoing"
    assert resolved.links[pct.applied_discount_id] == "pct_1000_ongoing"


async def test_resolve_no_discounts_is_empty() -> None:
    """A line with no discounts resolves to empty maps and creates no coupon."""
    fake = _FakeDiscountService()
    groups = {uuid4(): [_membership([])]}

    resolved = await PaymentSyncDiscounts(fake).resolve(groups, "acct_test")

    assert resolved.coupons_by_price == {}
    assert resolved.links == {}
    assert fake.created == []


# ── LineDiscountValue validators ────────────────────────────────────


@pytest.mark.parametrize("bad_percent", [0, -5, 100.01, 150])
def test_line_value_rejects_out_of_range_percent(bad_percent: float) -> None:
    """percentage_off must be 0 < p <= 100 — an impossible computed percent
    raises loudly instead of mis-billing."""
    with pytest.raises(ValidationError):
        LineDiscountValue(
            discount_mode=DiscountMode.ongoing, percentage_off=bad_percent
        )


def test_line_value_allows_boundary_percent_100() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=100.0
    )
    assert value.percentage_off == 100.0


@pytest.mark.parametrize("bad_dollar", [0, -5])
def test_line_value_rejects_non_positive_dollar(bad_dollar: int) -> None:
    with pytest.raises(ValidationError):
        LineDiscountValue(
            discount_mode=DiscountMode.once, dollar_off=bad_dollar
        )


def test_line_value_rejects_neither_percent_nor_dollar() -> None:
    with pytest.raises(ValidationError):
        LineDiscountValue(discount_mode=DiscountMode.ongoing)


def test_line_value_rejects_both_percent_and_dollar() -> None:
    with pytest.raises(ValidationError):
        LineDiscountValue(
            discount_mode=DiscountMode.ongoing,
            percentage_off=10.0,
            dollar_off=500,
        )
