"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.complexity import Complexity
from schema.primitives import AbsolutePath


class ImageOutput(BaseModel):
    """One generated image: where it is, the prompt that made it, the
    complexity tier that picked the generator's quality, and the
    style-adherence verdict.

    ``complexity``, ``adherent``, ``edited_prompt`` and ``edited_reason``
    are optional: the pipeline always sets ``complexity`` and ``adherent``,
    but older or externally-produced ``output.yaml`` files predate these
    fields and must still validate. ``adherent`` is the style verdict;
    ``edited_prompt``/``edited_reason`` are populated only when the image
    was off-style and a one-time corrective edit was applied (both stay
    ``None`` when adherent)."""

    model_config = ConfigDict(extra="forbid")

    path: AbsolutePath
    prompt: str
    complexity: Complexity | None = None
    adherent: bool | None = None
    edited_prompt: str | None = None
    edited_reason: str | None = None

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
