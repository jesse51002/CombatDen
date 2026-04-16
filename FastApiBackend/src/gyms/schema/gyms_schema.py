"""Pydantic schemas for the gyms domain."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class GymCreateRequest(BaseModel):
    """Payload for ``POST /api/v1/gyms/``."""

    gym_name: str = Field(min_length=1, max_length=255)
    owner_first_name: str = Field(min_length=1, max_length=255)
    owner_last_name: str = Field(min_length=1, max_length=255)

    @field_validator("gym_name", "owner_first_name", "owner_last_name")
    @classmethod
    def _strip_and_require_nonempty(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("must be a non-empty string")
        return stripped


class GymCreateResponse(BaseModel):
    """Response for ``POST /api/v1/gyms/``."""

    gym_id: UUID
    stripe_account_id: str
    stripe_onboarding_status: Literal["pending"]
    onboarding_url: str
    onboarding_url_expires_at: datetime


class GymOnboardingStatusResponse(BaseModel):
    """Response for ``GET /api/v1/gyms/me/onboarding``."""

    gym_id: UUID
    stripe_onboarding_status: Literal["pending", "complete", "disabled"]
    onboarding_url: str | None = None
    onboarding_url_expires_at: datetime | None = None
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    disabled_reason: str | None = None
    requirements_currently_due: list[str] = []


class GymOnboardingLinkResponse(BaseModel):
    """Response for ``POST /api/v1/gyms/me/onboarding/link``."""

    gym_id: UUID
    onboarding_url: str
    onboarding_url_expires_at: datetime
