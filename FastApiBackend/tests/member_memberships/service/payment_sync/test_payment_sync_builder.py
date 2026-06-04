"""Unit tests for pure builder logic in payment_sync_builder."""

import logging
from uuid import UUID, uuid4

import pytest
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    aggregate_plan_discounts,
)


def _membership(
    plan_id: UUID,
    discount_ids: list[UUID],
    member_id: UUID | None = None,
) -> ActiveMembershipRow:
    return ActiveMembershipRow(
        member_id=member_id or uuid4(),
        plan_id=plan_id,
        price_id=uuid4(),
        stripe_price_id="price_test",
        stripe_item_id="si_test",
        duration_unit=DurationUnit.month,
        discount_ids=discount_ids,
        price=1000,
    )


def test_resolves_crm_discount_ids_to_stripe_coupon_ids() -> None:
    plan_id = uuid4()
    d1 = uuid4()
    d2 = uuid4()
    coupon_map = {d1: "coupon_stripe_1", d2: "coupon_stripe_2"}

    result = aggregate_plan_discounts(
        [_membership(plan_id, [d1, d2])],
        coupon_map,
    )

    assert set(result.keys()) == {plan_id}
    coupons = {item.coupon for item in result[plan_id]}
    assert coupons == {"coupon_stripe_1", "coupon_stripe_2"}
    # Crucially, the CRM UUIDs must NOT appear as coupon strings.
    assert str(d1) not in coupons
    assert str(d2) not in coupons


def test_missing_discount_is_skipped_and_logs_warning(
    caplog: pytest.LogCaptureFixture,
) -> None:
    plan_id = uuid4()
    crm_user = uuid4()
    known = uuid4()
    missing = uuid4()
    coupon_map = {known: "coupon_stripe_known"}

    with caplog.at_level(
        logging.WARNING,
        logger="src.member_memberships.service.payment_sync.payment_sync_builder",
    ):
        result = aggregate_plan_discounts(
            [_membership(plan_id, [known, missing], member_id=crm_user)],
            coupon_map,
        )

    assert [item.coupon for item in result[plan_id]] == ["coupon_stripe_known"]
    assert any(
        str(missing) in record.getMessage() and record.levelno == logging.WARNING
        for record in caplog.records
    )


def test_same_plan_dedupes_on_coupon_string() -> None:
    plan_id = uuid4()
    d1 = uuid4()
    d2 = uuid4()
    d3 = uuid4()
    # d1 and d2 resolve to the SAME Stripe coupon — should collapse.
    coupon_map = {
        d1: "coupon_shared",
        d2: "coupon_shared",
        d3: "coupon_other",
    }

    result = aggregate_plan_discounts(
        [
            _membership(plan_id, [d1]),
            _membership(plan_id, [d2, d3]),
        ],
        coupon_map,
    )

    coupons = [item.coupon for item in result[plan_id]]
    assert sorted(coupons) == ["coupon_other", "coupon_shared"]


def test_empty_coupon_map_returns_empty_lists_per_plan() -> None:
    plan_id = uuid4()
    result = aggregate_plan_discounts(
        [_membership(plan_id, [uuid4(), uuid4()])],
        {},
    )

    assert result == {plan_id: []}


def test_no_memberships_returns_empty_mapping() -> None:
    assert aggregate_plan_discounts([], {}) == {}
