"""Validator tests for the one-off-card fields on the start request.

Pure-schema, no I/O — they lock in that a custom checkout card is card-only
and that the save-as-default flag requires a card.
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
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


def test_custom_card_alone_is_valid():
    req = _base(custom_payment_method_id="pm_1", custom_card_set_default=True)
    assert req.custom_payment_method_id == "pm_1"
    assert req.custom_card_set_default is True


def test_defaults_are_off():
    req = _base()
    assert req.custom_payment_method_id is None
    assert req.custom_card_set_default is False


def test_custom_card_rejected_with_cash():
    with pytest.raises(ValidationError):
        _base(custom_payment_method_id="pm_1", paid_with_cash=True)


def test_set_default_requires_a_card():
    with pytest.raises(ValidationError):
        _base(custom_card_set_default=True)
