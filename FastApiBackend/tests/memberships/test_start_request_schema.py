"""Validator tests for the start request (pure-schema + intra-request guard).

Pure, no I/O. The nested ``payment`` model is card-only (mutually exclusive
with cash). The "a recurring membership requires set_default" rule lives in
the start op (it needs the resolved plan types), not the schema. The schema no
longer rejects duplicate ``(member_id, price_id)`` items — N identical
one_time / trial items is how a member buys N copies of a pack — so the
"two recurring on the same plan in one request" rule moved to
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


def test_request_allows_duplicate_pairs():
    """The model no longer rejects duplicate (member_id, price_id) items."""
    member_id = uuid4()
    price_id = uuid4()
    req = MemberMembershipsStartRequest(
        payer_member_id=member_id,
        gym_id=uuid4(),
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(member_id=member_id, price_id=price_id),
            MemberMembershipsStartItem(member_id=member_id, price_id=price_id),
        ],
    )
    assert len(req.memberships) == 2


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
    """Two recurring items on the same (member, plan) in one request fail."""
    member_id = uuid4()
    price_id = uuid4()
    plan_prices = {
        price_id: {
            "plan_id": uuid4(),
            "plan_type": PlanType.recurring.value,
        },
    }
    request = _req(member_id, [price_id, price_id])
    with pytest.raises(ValueError, match="Duplicate recurring"):
        _validation()._check_no_recurring_duplicates(request, plan_prices)


def test_validation_allows_duplicate_one_time():
    """N identical one_time items pass — that is how you buy N packs."""
    member_id = uuid4()
    price_id = uuid4()
    plan_prices = {
        price_id: {
            "plan_id": uuid4(),
            "plan_type": PlanType.one_time.value,
        },
    }
    request = _req(member_id, [price_id, price_id])
    # No raise.
    _validation()._check_no_recurring_duplicates(request, plan_prices)
