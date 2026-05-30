"""Typed models for the text LLM call: per-slot wire shape and the
per-request closed wire schema builder.

The LLM is asked for ONLY the rewritten string per slot. There is no
prose / display name / provenance: each slot is identified by the
snake_case id it already carries in ``app.yaml`` (and that id is shown
to the LLM in the prompt with its description), so a second human
label would just drift.

Length-bounds validation lives on ``TextGenerationService`` and not in
a ``model_validator`` here — the service implements the user-asked
per-slot retry pattern (only-violating-slots, max 3 attempts), which
the existing ``complete_structured`` whole-batch retry loop can't
express. The closed wire model is responsible for completeness alone:
one required ``LLMTextResponse`` per requested slot id, so a missing
slot still surfaces as a ``ValidationError`` the existing retry loop
re-asks on for free.

Two things live here:

- ``LLMTextResponse`` — the narrow per-slot wire type the LLM fills in.
- The per-request closed model built by ``build_text_response_model``
  for the structured-output call itself.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model

TEXT_RESPONSE_MODEL_NAME = "TextSelection"


class LLMTextResponse(BaseModel):
    """What the LLM returns for one text slot.

    Just the rewritten string — the slot's id keys it in the parent
    closed model. Tight on purpose: structured output exposes this
    shape to the model and we only want the model to type the copy.
    """

    model_config = ConfigDict(extra="forbid")

    value: str


def build_text_response_model(slot_ids: list[str]) -> type[BaseModel]:
    """Closed per-request wire schema: one required ``LLMTextResponse``
    per slot id in this call.

    Anthropic strict structured output rejects open maps, so the schema
    sent to the LLM is built per request with an explicit, required
    field for every requested slot id (same approach as the colour and
    font modules). Slot ids come from app YAML and are already
    snake_case-validated (``SlotBase``), so they are valid Python
    identifiers and safe as model field names.

    Length-bounds enforcement is intentionally NOT a ``model_validator``
    here: the service runs a per-slot retry (only the violating slots
    re-call, up to ``MAX_RETRIES``), which an after-validator that
    raises ``ValueError`` can't express — the whole-batch retry loop on
    ``complete_structured`` would re-ask for every slot every time and
    cap at ``settings.llm_max_retries``. The service does the check
    itself and decides what to re-ask.

    The produced model keeps the stable name ``TextSelection`` so error
    messages, logs, and test dispatch stay meaningful.
    """
    return create_model(
        TEXT_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        **{slot_id: (LLMTextResponse, ...) for slot_id in slot_ids},
    )
