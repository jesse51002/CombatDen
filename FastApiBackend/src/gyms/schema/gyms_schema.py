"""Pydantic models for the gyms domain."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401


class GymCreateRequest(BaseModel):
    """Body for POST /api/v1/gyms/."""

    gym_name: str = Field(min_length=1, max_length=255)
    gym_description: str | None = None
    timezone: str = "America/Chicago"
    owner_first_name: str = Field(min_length=1, max_length=255)
    owner_last_name: str = Field(min_length=1, max_length=255)
    owner_phone: str | None = None
    owner_email: str | None = None

    @field_validator("gym_name", "owner_first_name", "owner_last_name")
    @classmethod
    def _strip_and_require_nonempty(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("must be a non-empty string")
        return stripped


class GymUpdateData(BaseModel):
    """Mutable fields on a gym row.

    Per project convention, update requests separate identity
    from a nested ``data`` model with only mutable optional fields.
    """

    gym_name: str | None = None
    gym_description: str | None = None
    timezone: str | None = None


class GymUpdateRequest(BaseModel):
    """Body for PUT /api/v1/gyms/{gym_id}."""

    data: GymUpdateData


class GymResponse(BaseModel):
    """A single gym row (basic fields, no Stripe state)."""

    gym_id: UUID
    gym_name: str
    gym_description: str | None
    timezone: str


class GymWithRoleResponse(GymResponse):
    """A gym the caller administers, annotated with their role.

    Returned by ``GET /api/v1/gyms/`` — the list of gyms the
    authenticated user owns or admins (``employee_type`` is the
    caller's role for that gym).
    """

    employee_type: EmployeeType


class GymEmployeeResponse(BaseModel):
    """A single gym_employees row."""

    employee_id: UUID
    gym_id: UUID
    user_id: UUID | None
    employee_type: str
    first_name: str
    last_name: str
    phone: str | None
    email: str | None
    employee_pic_url: str | None
    employee_public_description: str | None
    created_at: datetime


class GymCreateResponse(BaseModel):
    """Response for POST /api/v1/gyms/ (Stripe onboarding path).

    Returned after a new gym + Stripe Connect Express account are
    created.  The ``onboarding_url`` is short-lived (~5 minutes).
    """

    gym_id: UUID
    stripe_account_id: str
    stripe_onboarding_status: Literal["pending"]
    onboarding_url: str
    onboarding_url_expires_at: datetime


class GymOnboardingStatusResponse(BaseModel):
    """Response for GET /api/v1/gyms/{gym_id}/onboarding."""

    gym_id: UUID
    stripe_onboarding_status: Literal["not_started", "pending", "complete"]
    onboarding_url: str | None = None
    onboarding_url_expires_at: datetime | None = None
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    disabled_reason: str | None = None
    requirements_currently_due: list[str] = []


class GymOnboardingLinkResponse(BaseModel):
    """Response for POST /api/v1/gyms/{gym_id}/onboarding/link."""

    gym_id: UUID
    onboarding_url: str
    onboarding_url_expires_at: datetime
