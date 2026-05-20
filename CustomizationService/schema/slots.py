"""The customizable slot types: `ColorSlot`, `ImageSlot`, `FontSlot`, `TextSlot`."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from schema.color_role import ColorRole

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

# Sensible bounds the pipeline will clamp absurd YAML-supplied length
# limits into. A copy slot is "a button label, a screen title, or a short
# CTA" — 200 characters is already two long sentences; 40 words is a
# paragraph. Anything outside these is a YAML typo (someone wrote a
# million or zero), not a real product requirement.
TEXT_MAX_CHARS_CEILING = 200
TEXT_MAX_WORDS_CEILING = 40
TEXT_MAX_CHARS_FLOOR = 1
TEXT_MAX_WORDS_FLOOR = 1


class SlotBase(BaseModel):
    """Shared shape for every customizable slot."""

    model_config = ConfigDict(extra="forbid")

    id: str
    description: str

    @field_validator("id")
    @classmethod
    def _id_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"slot id {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("description")
    @classmethod
    def _description_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("slot description must be non-empty")
        return v


class ColorSlot(SlotBase):
    """A named color the pipeline will resolve to an oklch value.

    ``role`` is optional and validation-only: it is never sent to the LLM
    (the prompt infers role from the description). When set, it tells the
    deterministic contract which colours to contrast-test and sanity-bound.
    """

    role: ColorRole | None = None


class ImageSlot(SlotBase):
    """A named image the pipeline will generate and write to disk.

    ``depends_on`` lists other image slot ids whose resolved outputs this
    image builds on (visual continuity / one image feeding another). The
    colour palette is always an implicit dependency and is never listed
    here. Empty by default, so existing app.yaml files validate unchanged.
    Cross-reference checks (ids exist, no self-dep, no dupes, not the
    reserved key) live on ``AppFormat``; cycle detection lives on the
    executor graph — a slot in isolation cannot see its siblings.
    """

    depends_on: list[str] = Field(default_factory=list)


class FontSlot(SlotBase):
    """A named font role the pipeline will resolve to a Google Font family.

    Just ``id`` + ``description`` (inherited): the description is the
    only thing the LLM is shown, mirroring ``ColorSlot``'s pre-role
    shape. Per-slot role enums are intentionally deferred — pairing /
    legibility rules live in the prompt, not the type.
    """


class TextSlot(SlotBase):
    """A named copy slot the pipeline will rewrite to fit the brand.

    The LLM is shown the slot's ``description`` plus the brand brief and
    asked to produce a fresh string that fits the brand voice — there is
    no original copy in here. The MobileApp owns the default string in
    its own source; the pipeline output is an *override* the app applies
    when present, falling back to its own string otherwise.

    Length bounds are deterministic per-slot validation: the LLM is told
    them, and the pipeline programmatically checks every returned value
    against them. Out-of-band values silently clamp at parse time so a
    YAML typo (``max_chars: 1_000_000``, ``max_words: 0``) can't escape
    into the prompt or the validator — see the ``TEXT_*_FLOOR`` /
    ``TEXT_*_CEILING`` constants.
    """

    min_words: int = 1
    max_words: int
    min_chars: int = 1
    max_chars: int

    @field_validator("max_words")
    @classmethod
    def _clamp_max_words(cls, v: int) -> int:
        return max(TEXT_MAX_WORDS_FLOOR, min(v, TEXT_MAX_WORDS_CEILING))

    @field_validator("max_chars")
    @classmethod
    def _clamp_max_chars(cls, v: int) -> int:
        return max(TEXT_MAX_CHARS_FLOOR, min(v, TEXT_MAX_CHARS_CEILING))

    @field_validator("min_words")
    @classmethod
    def _clamp_min_words_floor(cls, v: int) -> int:
        # Min floors at 0 (no lower bound); the cross-field validator
        # below clamps it down to ``max_words`` once both are known.
        return max(0, min(v, TEXT_MAX_WORDS_CEILING))

    @field_validator("min_chars")
    @classmethod
    def _clamp_min_chars_floor(cls, v: int) -> int:
        return max(0, min(v, TEXT_MAX_CHARS_CEILING))

    @model_validator(mode="after")
    def _min_le_max(self) -> "TextSlot":
        if self.min_words > self.max_words:
            self.min_words = self.max_words
        if self.min_chars > self.max_chars:
            self.min_chars = self.max_chars
        return self
