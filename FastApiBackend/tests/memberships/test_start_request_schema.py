"""Validator tests for the optional checkout-card on the start request.

Pure-schema, no I/O. The nested ``payment`` model is card-only (mutually
exclusive with cash). The "a recurring membership requires set_default" rule
lives in the start op (it needs the resolved plan types), not the schema.
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartPayment,
    MemberMembershipsStartRequest,
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
