"""Pydantic models for the image module: prompt-building + outputs."""

from __future__ import annotations

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from schema import Complexity, DependencyUsage


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


class DependencyUsageEntry(BaseModel):
    """One declared image dependency and how it should inform this image.

    ``dependency`` is the dependency slot's id (exactly as listed in the
    prompt); ``usage`` is the model's ``reference``/``direct`` verdict.
    """

    model_config = ConfigDict(extra="forbid")

    dependency: str
    usage: DependencyUsage


class ImagePrompt(BaseModel):
    """The prompt build: ``prompt`` flows on to the generator, and
    ``dependency_usage`` carries the per-dependency ``reference``/``direct``
    verdict the same call makes while writing the prompt.

    ``dependency_usage`` is an empty list when the slot declares no image
    dependencies (the prompt is told to return an empty list, and the
    field defaults to empty if the model omits it). It is a *list* of
    entries, not a map: structured-output schemas honour arrays of objects
    far more reliably than a dict-of-enum (``additionalProperties``). The
    image node converts and validates it against the slot's declared
    dependencies.

    ``rationale`` is commented out: it sat *after* ``prompt`` in the
    schema, so structured output generated it too late to sharpen the
    prompt anyway. To bring it back, uncomment the field, add
    ``"rationale"`` back to the validator, and restore the rationale
    instruction in ``prompts/image_prompt_rule.md`` (keep schema and
    prompt consistent — ``extra="forbid"`` rejects a stray field)."""

    model_config = ConfigDict(extra="forbid")

    prompt: str
    dependency_usage: list[DependencyUsageEntry] = Field(
        default_factory=list
    )

    @field_validator("prompt")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImagePrompt fields must be non-empty")
        return v
