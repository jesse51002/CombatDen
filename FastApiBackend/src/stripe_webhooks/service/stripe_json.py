"""JSON serialization for raw Stripe webhook payloads."""

import json
from decimal import Decimal
from typing import Any


def _json_default(obj: Any) -> Any:
    """Fallback encoder for types ``json`` can't natively serialize.

    Stripe's ``Event.to_dict()`` yields ``Decimal`` for decimal-string
    fields (e.g. ``unit_amount_decimal``); render those as ``float``.
    Any other unexpected type is stringified so an audit-payload write
    can never crash a webhook.
    """
    if isinstance(obj, Decimal):
        return float(obj)
    return str(obj)


def dump_stripe_payload(payload: dict[str, Any]) -> str:
    """Serialize a raw Stripe payload to a JSON string for JSONB storage."""
    return json.dumps(payload, default=_json_default)
