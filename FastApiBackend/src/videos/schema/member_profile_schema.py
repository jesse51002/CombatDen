from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Hard cap on the LLM summary length (cost/DB guard, not a prompt target).
MAX_PROFILE_SUMMARY_CHARS = 1200


class MemberProfileSummary(BaseModel):
    """The LLM's one-paragraph video-taste summary for a member."""

    model_config = ConfigDict(extra="ignore")
    summary: str = Field(min_length=1)

    @field_validator("summary", mode="after")
    @classmethod
    def _cap(cls, value: str) -> str:
        return value[:MAX_PROFILE_SUMMARY_CHARS]
