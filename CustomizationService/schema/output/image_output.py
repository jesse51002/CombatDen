"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.primitives import AbsolutePath


class ImageOutput(BaseModel):
    """One generated image: where it is, and the prompt that made it."""

    model_config = ConfigDict(extra="forbid")

    path: AbsolutePath
    prompt: str

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
