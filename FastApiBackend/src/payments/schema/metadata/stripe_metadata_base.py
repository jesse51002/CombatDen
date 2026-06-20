"""Shared base for typed Stripe metadata models.

Each Stripe resource kind we write has its own subclass that declares
exactly the fields it needs. All subclasses inherit ``to_stripe_metadata``
(serialize → ``dict[str, str]`` for Stripe's wire format) and
``from_stripe_metadata`` (parse Stripe's ``dict[str, str]`` back into
the typed envelope, with bool fields coerced from Stripe's string
convention).

``extra="forbid"`` ensures a caller can't silently pass a key that
doesn't belong on the resource — if you need a new key, add it as a
typed field on the relevant subclass.
"""

from __future__ import annotations

import json
from typing import Any, get_origin

from pydantic import BaseModel, ConfigDict


class BaseStripeMetadata(BaseModel):
    """Base class for per-resource Stripe metadata models."""

    model_config = ConfigDict(extra="forbid")

    def to_stripe_metadata(self) -> dict[str, str]:
        """Serialize to Stripe's ``dict[str, str]`` metadata shape.

        UUIDs become their string form; bools become ``"true"`` /
        ``"false"``; list fields become a JSON-array string (Stripe
        metadata values are strings only, so e.g. ``paid_for`` rides as
        ``'["<uuid>", ...]'``); ``None`` values are dropped so Stripe does
        not receive the literal string ``"None"``.
        """
        dumped = self.model_dump(exclude_none=True, mode="json")
        out: dict[str, str] = {}
        for key, value in dumped.items():
            if isinstance(value, bool):
                out[key] = "true" if value else "false"
            elif isinstance(value, list):
                out[key] = json.dumps(value)
            else:
                out[key] = str(value)
        return out

    @classmethod
    def from_stripe_metadata(
        cls,
        raw: dict[str, str] | None,
    ) -> BaseStripeMetadata:
        """Parse Stripe's ``dict[str, str]`` back into the typed envelope.

        Bool fields (discovered via ``cls.model_fields``) are coerced
        from Stripe's ``"true"`` / ``"false"`` string convention; list
        fields are JSON-decoded back from their array string (the inverse
        of ``to_stripe_metadata``). Other fields are handed to Pydantic
        for validation/coercion.
        """
        raw = raw or {}
        normalized: dict[str, Any] = dict(raw)
        for field_name, info in cls.model_fields.items():
            if field_name not in normalized:
                continue
            annotation = info.annotation
            value = normalized[field_name]
            if annotation is bool or annotation == (bool | None):
                normalized[field_name] = str(value).lower() == "true"
            elif get_origin(annotation) is list and isinstance(value, str):
                normalized[field_name] = json.loads(value)
        return cls.model_validate(normalized)
