"""Typed models for the font LLM call: per-slot wire shape and the
per-request closed wire schema builder.

The LLM is asked for ONLY the family name plus the prose fields
(``display_name``, ``description``). ``category`` is read off the
Google Fonts catalog entry by the writer after the catalog confirms
the family exists — never asked of the LLM — so it cannot drift from
what Google actually serves.

Two things live here:

- ``LLMFontResponse`` — the narrow per-slot wire type the LLM fills in.
- The per-request closed model built by ``build_font_response_model``
  for the structured-output call itself. Its
  ``model_validator(mode="after")`` checks every picked family against
  a pre-loaded snapshot of the Google Fonts catalog; a miss surfaces
  as a Pydantic ``ValidationError`` and re-rides the existing
  ``complete_structured`` retry loop. Zero new retry code.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

FONT_RESPONSE_MODEL_NAME = "FontSelection"


class LLMFontResponse(BaseModel):
    """What the LLM returns for one font slot.

    Narrow on purpose: the model only picks ``family`` (plus the prose
    fields). ``category`` and per-variant ``files`` come from the Google
    Fonts catalog after validation, so they cannot drift.
    """

    model_config = ConfigDict(extra="forbid")

    family: str
    display_name: str
    description: str


def build_font_response_model(
    slot_ids: list[str],
    *,
    known_families: frozenset[str],
) -> type[BaseModel]:
    """Closed per-request wire schema: one required ``LLMFontResponse`` per
    slot, plus a Google-Fonts-membership check as an after-validator.

    Anthropic strict structured output rejects open maps, so the schema
    sent to the LLM is built per request with an explicit, required
    field for every requested slot id (same approach as the colour
    module). Slot ids come from app YAML and are already
    snake_case-validated (``SlotBase``), so they are valid Python
    identifiers and safe as model field names.

    ``known_families`` is a lowercased snapshot of the Google Fonts
    catalog — the validator is sync, so the caller pre-awaits the
    snapshot and feeds it in. A picked family that isn't in the set
    raises ``ValueError`` which Pydantic wraps as a ``ValidationError``;
    ``LiteLLMClient.complete_structured`` catches that and re-asks via
    ``schema_correction.md`` — no font-specific retry loop.
    """

    def _check_families(self: BaseModel) -> BaseModel:
        bad = sorted(
            {
                slot_id
                for slot_id in slot_ids
                if getattr(self, slot_id).family.lower() not in known_families
            }
        )
        if bad:
            picks = ", ".join(
                f"{slot_id}={getattr(self, slot_id).family!r}"
                for slot_id in bad
            )
            raise ValueError(
                "every font family must be a real Google Fonts family "
                "(case-insensitive match against the live catalog). "
                f"Not found on Google Fonts: {picks}. Pick a different "
                "family for each of these slots; check fonts.google.com "
                "for the exact canonical spelling."
            )
        return self

    return create_model(
        FONT_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_google_fonts_membership": model_validator(mode="after")(
                _check_families
            )
        },
        **{slot_id: (LLMFontResponse, ...) for slot_id in slot_ids},
    )
