"""ColorPalette — the colour module's output model, plus the per-request
closed wire schema builder for the colour LLM call."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

from schema import ColorOutput, ColorRole
from src.modules.colors.color_validation import enforce_color_contract

COLOR_RESPONSE_MODEL_NAME = "ColorPalette"


class ColorPalette(BaseModel):
    """The colour module's output: every colour slot resolved."""

    model_config = ConfigDict(extra="forbid")

    colors: dict[str, ColorOutput]


def build_color_response_model(
    slot_ids: list[str],
    *,
    roles: dict[str, ColorRole | None],
    dark_mode: bool,
) -> type[BaseModel]:
    """Closed per-request wire schema: one required ``ColorOutput`` per slot,
    plus the deterministic colour contract as an after-validator.

    Anthropic strict structured output rejects open maps — ``dict[str, X]``
    renders ``additionalProperties`` as a schema, which it forbids. So the
    schema sent for the colour call is built per request with an explicit,
    *required* field for every requested slot id. Slot ids come from app
    YAML and are already snake_case-validated (``SlotBase``), so they are
    valid Python identifiers and safe as model field names.

    Completeness is therefore structural: a missing slot is a Pydantic
    ``ValidationError`` the llm client's retry loop re-asks on. The same
    loop also drives the cross-slot contrast/sanity contract: the
    closure-captured ``model_validator(mode="after")`` runs
    ``enforce_color_contract`` (which needs the slot→role map + dark_mode,
    neither of which is in the LLM response), and a raised ``ValueError``
    surfaces as a ``ValidationError`` the existing ``complete_structured``
    loop catches and feeds back via ``schema_correction.md`` — zero new
    loop code, faithful to "the same retry pattern".

    The produced model keeps the stable name ``ColorPalette`` so error
    messages, logs, and test dispatch stay meaningful.
    """

    def _check_palette(self: BaseModel) -> BaseModel:
        enforce_color_contract(
            {slot_id: getattr(self, slot_id) for slot_id in slot_ids},
            roles=roles,
            dark_mode=dark_mode,
        )
        return self

    return create_model(
        COLOR_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_color_contract": model_validator(mode="after")(
                _check_palette
            )
        },
        **{slot_id: (ColorOutput, ...) for slot_id in slot_ids},
    )
