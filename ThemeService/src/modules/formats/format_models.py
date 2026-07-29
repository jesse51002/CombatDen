"""Typed models for the format LLM call: the per-slot wire shape and the
per-request closed wire schema builder.

The LLM is asked for one chosen value plus a one-line reason per slot, in
ONE call covering every slot in the request. Each slot is identified by
the snake_case id it already carries in ``app.yaml`` (shown to the LLM in
the prompt with its description and its own vocabulary), so no second
human label is needed.

**Why the vocabularies are enforced by an after-validator, not static
enums.** Each slot's values are the *app's own* (``app.yaml`` →
``formats[].values[].value``), so no enum can exist in Python without
breaking the app-agnostic rule — and unlike the classification node there
is not one vocabulary but one **per slot**. The schema is therefore built
per request from the app's own lists and membership is enforced by a
single after-validator that checks every field against ITS OWN slot's
values, naming only the offenders. That is the icon module's matching
pattern (``build_icon_match_model``) applied per-slot instead of
per-set: a miss raises ``ValueError`` → Pydantic ``ValidationError`` →
the existing ``complete_structured`` retry loop re-asks with the error
text (which names the offending slots and their permitted values) folded
in. Zero new retry code, and no dependence on a provider's strict-mode
``enum`` support.

A **missing** slot needs no validator at all: every field is required on
the closed model, so an omitted slot is a ``ValidationError`` the same
loop re-asks on for free.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

from schema import FormatSlot

FORMAT_RESPONSE_MODEL_NAME = "FormatSelection"


class LLMFormatResponse(BaseModel):
    """What the LLM returns for one format slot.

    ``value`` is the chosen token, copied verbatim from that slot's
    declared vocabulary; ``reason`` is the one-line justification kept on
    the artifact so a run's arrangement decisions stay reviewable.
    """

    model_config = ConfigDict(extra="forbid")

    value: str
    reason: str


def build_format_response_model(
    slots: list[FormatSlot],
) -> type[BaseModel]:
    """Closed per-request schema for the format call: one
    ``LLMFormatResponse`` per slot, plus a per-slot vocabulary
    after-validator.

    ``slots`` is the subset being resolved on this call (every declared
    slot on a fresh run; only the dirty ones on a partial regen), so the
    schema — and therefore the validator — always matches what was asked.
    Slot ids come from app YAML and are snake_case-validated
    (``SlotBase``), so they are valid Python identifiers and safe as model
    field names.

    The produced model keeps the stable name ``FormatSelection`` so error
    messages, logs, and test-fake dispatch stay meaningful.
    """
    vocabulary = {
        slot.id: frozenset(entry.value for entry in slot.values)
        for slot in slots
    }

    def _check_members(self: BaseModel) -> BaseModel:
        bad = sorted(
            slot_id
            for slot_id, allowed in vocabulary.items()
            if getattr(self, slot_id).value not in allowed
        )
        if bad:
            detail = "; ".join(
                f"{slot_id}={getattr(self, slot_id).value!r} "
                f"(allowed: {sorted(vocabulary[slot_id])})"
                for slot_id in bad
            )
            raise ValueError(
                "every format value must be one of ITS OWN slot's declared "
                f"values. Rejected: {detail}. Re-answer ONLY those slots "
                "with a value copied verbatim from that slot's list — same "
                "spelling, same capitalization — and keep the values you "
                "already gave for the other slots. Do not invent a value, "
                "reuse another slot's value, or rephrase one."
            )
        return self

    return create_model(
        FORMAT_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_declared_vocabulary": model_validator(mode="after")(
                _check_members
            )
        },
        **{slot.id: (LLMFormatResponse, ...) for slot in slots},
    )
