"""Pydantic models for the image module: prompt-building + outputs."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator


class BackgroundCheck(BaseModel):
    """Structured verdict from the Gemini-vision background validator."""

    model_config = ConfigDict(extra="forbid")

    ok: bool
    reason: str


class ImagePrompt(BaseModel):
    """The prompt build: ``rationale`` only sharpens the model, just
    ``prompt`` flows on to the generator."""

    model_config = ConfigDict(extra="forbid")

    prompt: str
    rationale: str

    @field_validator("prompt", "rationale")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImagePrompt fields must be non-empty")
        return v
