"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.complexity import Complexity
from schema.primitives import AbsolutePath


class ImageOutput(BaseModel):
    """One generated image: where it is, the prompt that made it, and the
    complexity tier that picked the generator's quality.

    ``complexity`` is optional: every fresh run sets it, but older or
    externally-produced ``output.yaml`` files predate it and must still
    validate. ``extra="ignore"`` (not the package-wide ``forbid``) is a
    deliberate exception: this model is read back from externally- or
    previously-produced ``output.yaml`` files that may carry now-removed
    keys (``adherent``, ``edited_prompt``, ``edited_reason``,
    ``dependency_usage``) — those are silently dropped, not rejected."""

    model_config = ConfigDict(extra="ignore")

    path: AbsolutePath
    prompt: str
    complexity: Complexity | None = None

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
