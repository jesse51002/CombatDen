"""Typed models for the icon LLM calls: the per-slot wire shapes and the
per-request closed wire schemas for the three structured calls.

The icon module makes three structured LLM calls, each with a closed
per-request model (Anthropic strict structured output rejects open maps,
so the schema is built per request with an explicit field per slot id —
the same approach the font and colour modules use):

1. **Set selection** — ``build_icon_set_selection_model`` returns a model
   with one ``icon_set`` field constrained (after-validator) to the known
   set ids. The LLM picks the best-fit set by brand vibe.
2. **Matching** — ``build_icon_match_model`` returns a model with one
   ``LLMIconResponse`` per slot; its after-validator checks every
   non-null pick against the chosen set's icon names. A null pick is the
   honest "no icon in this set fits" answer and routes the slot to
   generation.
3. **Prompt authoring** — ``build_icon_prompt_model`` returns a model
   with one ``LLMIconPrompt`` per *unmatched* slot: the Recraft prompt the
   generator will render.

Membership misses raise ``ValueError`` → Pydantic ``ValidationError`` →
they re-ride the existing ``complete_structured`` retry loop. Zero new
retry code. Model ``__name__``s are stable so a test fake can dispatch on
them.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

ICON_SET_SELECTION_MODEL_NAME = "IconSetSelection"
ICON_MATCH_MODEL_NAME = "IconMatch"
ICON_PROMPT_MODEL_NAME = "IconPrompt"


class LLMIconResponse(BaseModel):
    """What the LLM returns for one icon slot during matching.

    ``icon`` is the matched icon's short-name from the chosen set, or
    ``None`` when no icon in the set honestly represents the slot (the
    pipeline then generates one). ``match_reason`` is short record-keeping
    prose — why this icon, or why nothing fit.
    """

    model_config = ConfigDict(extra="forbid")

    icon: str | None
    match_reason: str


class LLMIconPrompt(BaseModel):
    """What the LLM returns for one unmatched slot during prompt authoring.

    ``name`` is a short icon name (snake_case-ish, the kind a real icon set
    uses) the generated icon is recorded under; ``prompt`` is the Recraft
    prompt describing the SVG icon to generate.
    """

    model_config = ConfigDict(extra="forbid")

    name: str
    prompt: str


def build_icon_set_selection_model(
    set_ids: frozenset[str],
) -> type[BaseModel]:
    """Closed per-request schema for the set-selection call.

    One ``icon_set`` field (the chosen set id) plus a ``reason``, with an
    after-validator constraining ``icon_set`` to a known set id. A pick
    outside the catalog raises ``ValueError`` → ``ValidationError`` and
    re-rides the structured-output retry loop.
    """

    def _check_set(self: BaseModel) -> BaseModel:
        if self.icon_set not in set_ids:
            raise ValueError(
                f"icon_set must be one of the known set ids {sorted(set_ids)}; "
                f"got {self.icon_set!r}. Pick the single best-fit set."
            )
        return self

    return create_model(
        ICON_SET_SELECTION_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_known_set": model_validator(mode="after")(_check_set)
        },
        icon_set=(str, ...),
        reason=(str, ...),
    )


def build_icon_match_model(
    slot_ids: list[str],
    *,
    icon_names: frozenset[str],
) -> type[BaseModel]:
    """Closed per-request schema for the matching call: one
    ``LLMIconResponse`` per slot, plus a set-membership after-validator.

    ``icon_names`` is the chosen set's icon short-names. Every non-null
    pick must be a member; a null pick is allowed (honest no-match). Slot
    ids come from app YAML and are snake_case-validated, so they are safe
    Python field names. A non-member pick raises ``ValueError`` →
    ``ValidationError`` → re-asked via the existing retry loop.
    """

    def _check_members(self: BaseModel) -> BaseModel:
        bad = sorted(
            {
                slot_id
                for slot_id in slot_ids
                if (pick := getattr(self, slot_id).icon) is not None
                and pick not in icon_names
            }
        )
        if bad:
            picks = ", ".join(
                f"{slot_id}={getattr(self, slot_id).icon!r}" for slot_id in bad
            )
            raise ValueError(
                "every matched icon must be one of the chosen set's icon "
                f"names. Not in the set: {picks}. Either pick a real icon "
                "from the set for each, or return null to signal no honest "
                "match (the pipeline will generate one)."
            )
        return self

    return create_model(
        ICON_MATCH_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_set_membership": model_validator(mode="after")(
                _check_members
            )
        },
        **{slot_id: (LLMIconResponse, ...) for slot_id in slot_ids},
    )


def build_icon_prompt_model(slot_ids: list[str]) -> type[BaseModel]:
    """Closed per-request schema for the prompt-authoring call: one
    ``LLMIconPrompt`` per unmatched slot. No validator — the prompt is
    free text the generator renders."""
    return create_model(
        ICON_PROMPT_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        **{slot_id: (LLMIconPrompt, ...) for slot_id in slot_ids},
    )
