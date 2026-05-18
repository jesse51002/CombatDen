"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.complexity import Complexity
from schema.dependency_usage import DependencyUsage
from schema.primitives import AbsolutePath


class ImageOutput(BaseModel):
    """One generated image: where it is, the prompt that made it, the
    complexity tier that picked the generator's quality, and the
    style-adherence verdict.

    ``complexity``, ``adherent``, ``edited_prompt``, ``edited_reason`` and
    ``dependency_usage`` are optional: the pipeline always sets
    ``complexity`` and ``adherent``, but older or externally-produced
    ``output.yaml`` files predate these fields and must still validate.
    ``adherent`` is the style verdict; ``edited_prompt``/``edited_reason``
    are populated only when the image was off-style and a one-time
    corrective edit was applied (both stay ``None`` when adherent).
    ``dependency_usage`` maps each declared image dependency's slot id to
    how it informed this image (``reference`` folded into the prompt text,
    ``direct`` fed in as an input image); it is ``None`` when the slot
    declares no image dependencies."""

    model_config = ConfigDict(extra="forbid")

    path: AbsolutePath
    prompt: str
    complexity: Complexity | None = None
    adherent: bool | None = None
    edited_prompt: str | None = None
    edited_reason: str | None = None
    dependency_usage: dict[str, DependencyUsage] | None = None

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
