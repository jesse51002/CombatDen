"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.complexity import Complexity
from schema.primitives import AbsolutePath


class ImageOutput(BaseModel):
    """One generated image: where it is, the prompt that made it, and the
    complexity tier that picked the generator's quality.

    ``complexity`` is optional: the pipeline always sets it, but older or
    externally-produced ``output.yaml`` files predate the field and must
    still validate."""

    model_config = ConfigDict(extra="forbid")

    path: AbsolutePath
    prompt: str
    complexity: Complexity | None = None

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
