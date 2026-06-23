"""Validator tests for the start request (pure-schema + intra-request guard).

Pure, no I/O. The nested ``payment`` model is card-only (mutually exclusive
with cash). The "a recurring membership requires set_default" rule lives in
the start op (it needs the resolved plan types), not the schema. The schema
rejects duplicate ``(member_id, price_id)`` items — buying N of a pack is ONE
item with ``quantity = N``, never N duplicate items. The separate "two recurring
on the same plan (at different prices) in one request" rule lives in
``MemberMembershipsStartValidation._check_no_recurring_duplicates``, which is
unit-tested here (it is pure: no I/O, deps unused).
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartPayment,
    MemberMembershipsStartRequest,
)
from src.memberships.service.memberships_start_validation import (
    MemberMembershipsStartValidation,
)


def _base(**kw):
    return MemberMembershipsStartRequest(
        payer_member_id=uuid4(),
        gym_id=uuid4(),
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(member_id=uuid4(), price_id=uuid4()),
        ],
        **kw,
    )


def test_payment_is_valid():
    req = _base(
        payment=MemberMembershipsStartPayment(
            payment_method_id="pm_1",
            set_default=True,
        ),
    )
    assert req.payment is not None
    assert req.payment.payment_method_id == "pm_1"
    assert req.payment.set_default is True


def test_set_default_defaults_false():
    payment = MemberMembershipsStartPayment(payment_method_id="pm_1")
    assert payment.set_default is False


def test_no_payment_is_valid():
    assert _base().payment is None


def test_payment_rejected_with_cash():
    with pytest.raises(ValidationError):
        _base(
            payment=MemberMembershipsStartPayment(payment_method_id="pm_1"),
            paid_with_cash=True,
        )


def test_request_rejects_duplicate_pairs():
    """Two items sharing (member_id, price_id) are rejected — buying N of a
    pack is ONE item with quantity = N, never N duplicate items."""
    member_id = uuid4()
    price_id = uuid4()
    with pytest.raises(ValidationError):
        MemberMembershipsStartRequest(
            payer_member_id=member_id,
            gym_id=uuid4(),
            idempotency_key=uuid4(),
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member_id, price_id=price_id,
                ),
                MemberMembershipsStartItem(
                    member_id=member_id, price_id=price_id,
                ),
            ],
        )


def _req(member_id, price_ids):
    return MemberMembershipsStartRequest(
        payer_member_id=member_id,
        gym_id=uuid4(),
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(member_id=member_id, price_id=pid)
            for pid in price_ids
        ],
    )


def _validation():
    # _check_no_recurring_duplicates is pure — the deps go unused.
    return MemberMembershipsStartValidation(None, None, None, None)


def test_validation_rejects_duplicate_recurring():
    """Two recurring items on the same (member, plan) at DIFFERENT prices fail.

    The (member, price) request dedup can't see this (the prices differ), so the
    recurring same-plan guard is what catches it.
    """
    member_id = uuid4()
    price_a, price_b = uuid4(), uuid4()
    plan_id = uuid4()
    plan_prices = {
        price_a: {"plan_id": plan_id, "plan_type": PlanType.recurring.value},
        price_b: {"plan_id": plan_id, "plan_type": PlanType.recurring.value},
    }
    request = _req(member_id, [price_a, price_b])
    with pytest.raises(ValueError, match="Duplicate recurring"):
        _validation()._check_no_recurring_duplicates(request, plan_prices)


def test_validation_allows_two_one_time_on_same_plan():
    """Two one_time items on the same plan at DIFFERENT prices pass the guard —
    only recurring is one-per-plan; one_time / trial packs may stack."""
    member_id = uuid4()
    price_a, price_b = uuid4(), uuid4()
    plan_id = uuid4()
    plan_prices = {
        price_a: {"plan_id": plan_id, "plan_type": PlanType.one_time.value},
        price_b: {"plan_id": plan_id, "plan_type": PlanType.one_time.value},
    }
    request = _req(member_id, [price_a, price_b])
    # No raise — _check_no_recurring_duplicates only guards recurring.
    _validation()._check_no_recurring_duplicates(request, plan_prices)
