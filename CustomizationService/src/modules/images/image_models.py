"""Pydantic models for the image module: prompt-building + outputs."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from schema import Complexity


class ImageComplexity(BaseModel):
    """Structured verdict from the prompt-complexity classifier."""

    model_config = ConfigDict(extra="forbid")

    complexity: Complexity


class StyleCheck(BaseModel):
    """Structured verdict from the style-adherence classifier.

    One small vision call decides whether the generated image actually
    realises the prompt that produced it. ``adherent`` is the whole
    verdict; on a miss ``edit_instruction`` carries *only what to change*
    to bring that prompt's style to life — never a description of the
    current image and never new creative direction. Both text fields are
    empty when adherent."""

    model_config = ConfigDict(extra="forbid")

    adherent: bool
    reason: str
    edit_instruction: str

    @model_validator(mode="after")
    def _instruction_present_when_off_style(self) -> "StyleCheck":
        # A non-adherent verdict that carries no fix is unusable; reject
        # it so the client's existing re-ask loop asks again.
        if not self.adherent and not self.edit_instruction.strip():
            raise ValueError(
                "StyleCheck.edit_instruction must be non-empty when "
                "adherent is false"
            )
        return self


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

    @field_validator("prompt")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImagePrompt fields must be non-empty")
        return v
