"""Pydantic models for the image module: prompt-building + outputs."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema import Complexity


class ImageComplexity(BaseModel):
    """Structured verdict from the prompt-complexity classifier."""

    model_config = ConfigDict(extra="forbid")

    complexity: Complexity


class BackgroundCheck(BaseModel):
    """Structured verdict from the Gemini-vision background validator."""

    model_config = ConfigDict(extra="forbid")

    ok: bool
    reason: str


class ImagePrompt(BaseModel):
    """The prompt build: just ``prompt`` flows on to the generator.

    ``rationale`` is commented out: it sat *after* ``prompt`` in the
    schema, so structured output generated it too late to sharpen the
    prompt anyway. To bring it back, uncomment the field, add
    ``"rationale"`` back to the validator, and restore the rationale
    instruction in ``prompts/image_prompt_rule.md`` (keep schema and
    prompt consistent — ``extra="forbid"`` rejects a stray field)."""

    model_config = ConfigDict(extra="forbid")

    prompt: str
    # rationale: str

    @field_validator("prompt")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImagePrompt fields must be non-empty")
        return v
