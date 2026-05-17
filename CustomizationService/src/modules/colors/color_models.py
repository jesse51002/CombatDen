"""ColorPalette — the colour module's output model, plus the per-request
closed wire schema builder for the colour LLM call."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model

from schema import ColorOutput

COLOR_RESPONSE_MODEL_NAME = "ColorPalette"


class ColorPalette(BaseModel):
    """The colour module's output: every colour slot resolved."""

    model_config = ConfigDict(extra="forbid")

    colors: dict[str, ColorOutput]


def build_color_response_model(slot_ids: list[str]) -> type[BaseModel]:
    """Closed per-request wire schema: one required ``ColorOutput`` per slot.

    Anthropic strict structured output rejects open maps — ``dict[str, X]``
    renders ``additionalProperties`` as a schema, which it forbids. So the
    schema sent for the colour call is built per request with an explicit,
    *required* field for every requested slot id. Slot ids come from app
    YAML and are already snake_case-validated (``SlotBase``), so they are
    valid Python identifiers and safe as model field names.

    Completeness is therefore structural: a missing slot is a Pydantic
    ``ValidationError`` the llm client's retry loop re-asks on. The produced
    model keeps the stable name ``ColorPalette`` so error messages, logs,
    and test dispatch stay meaningful.
    """
    return create_model(
        COLOR_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        **{slot_id: (ColorOutput, ...) for slot_id in slot_ids},
    )
