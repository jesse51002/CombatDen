"""Unit tests for ``dump_stripe_payload``.

Regression guard for the production incident where ``invoice.paid``
webhooks 500'd: ``stripe.Event.to_dict()`` preserves ``Decimal`` for
decimal-string fields (e.g. ``lines.data[].pricing.unit_amount_decimal``),
which the stdlib ``json.dumps`` cannot serialize.
"""

import json
from decimal import Decimal

from src.stripe_webhooks.service.stripe_json import dump_stripe_payload


def test_decimal_unit_amount_serializes_as_float() -> None:
    # Mirrors the exact shape that crashed production.
    payload = {
        "id": "in_test_1",
        "lines": {
            "data": [
                {
                    "id": "il_test_0",
                    "pricing": {"unit_amount_decimal": Decimal("2000")},
                }
            ]
        },
    }

    decoded = json.loads(dump_stripe_payload(payload))

    unit_amount = decoded["lines"]["data"][0]["pricing"]["unit_amount_decimal"]
    assert unit_amount == 2000.0
    assert isinstance(unit_amount, float)


def test_plain_payload_round_trips_unchanged() -> None:
    payload = {"id": "in_test_2", "amount_paid": 5000, "currency": "usd"}

    assert json.loads(dump_stripe_payload(payload)) == payload


def test_unknown_type_is_stringified_not_raised() -> None:
    class Weird:
        def __str__(self) -> str:
            return "weird-value"

    decoded = json.loads(dump_stripe_payload({"x": Weird()}))

    assert decoded["x"] == "weird-value"
