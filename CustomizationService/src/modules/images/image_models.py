"""Pydantic models for the image module: prompt-building + outputs."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema import Complexity


class ImageComplexity(BaseModel):
    """Structured verdict from the prompt-complexity classifier."""

    model_config = ConfigDict(extra="forbid")

    complexity: Complexity


class ImagePrompt(BaseModel):
    """The prompt build: ``prompt`` flows on to the generator.

    Declared image dependencies are always treated as *reference* — their
    look is folded into ``prompt`` text for visual continuity by the
    prompt-writing call itself; nothing is fed to the generator as an
    input image and the model returns no per-dependency verdict.

    ``rationale`` is commented out: it sat *after* ``prompt`` in the
    schema, so structured output generated it too late to sharpen the
    prompt anyway. To bring it back, uncomment the field, add
    ``"rationale"`` back to the validator, and restore the rationale
    instruction in ``prompts/image_prompt_rule.md`` (keep schema and
    prompt consistent — ``extra="forbid"`` rejects a stray field)."""

    model_config = ConfigDict(extra="forbid")

    prompt: str

    @field_validator("prompt")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImagePrompt fields must be non-empty")
        return v
