"""Pydantic models for the gyms domain."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator
from schema.gym import StripeOnboardingStatus
from schema.gym_employee import EmployeeType, ThemeMode
from schema.gym_rank import SubRankType

import src.shared.db_schema_path  # noqa: F401


class GymCreateRequest(BaseModel):
    """Body for POST /api/v1/gyms/."""

    gym_name: str = Field(min_length=1, max_length=255)
    gym_description: str | None = None
    timezone: str = "America/Chicago"
    owner_first_name: str = Field(min_length=1, max_length=255)
    owner_last_name: str = Field(min_length=1, max_length=255)
    owner_phone: str | None = None

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
    # NOT NULL on the gyms row (DEFAULT 'stripes'), same as gym_name /
    # timezone below — explicit null is rejected, not a valid "clear".
    sub_rank_type: SubRankType | None = None
    # Nullable, unlike a reward's image: explicit null clears the logo
    # back to NULL (no logo uploaded). Absent = unchanged.
    logo_url: str | None = None

    @field_validator("gym_name", "timezone", "sub_rank_type")
    @classmethod
    def _reject_explicit_null(
        cls, value: str | SubRankType | None, info
    ) -> str | SubRankType | None:
        """gym_name / timezone / sub_rank_type are NOT NULL columns: an
        explicit ``null`` would reach the dynamic SET clause as a NOT
        NULL violation (500), so reject it here as a 422. Only runs when
        the field is present in the request body (Pydantic skips
        validators on an unset default), so an absent field still means
        "unchanged". ``gym_description`` and ``logo_url`` are genuinely
        nullable and stay clearable via explicit null."""
        if value is None:
            raise ValueError(
                f"{info.field_name} cannot be cleared; omit the field "
                "to leave it unchanged"
            )
        return value


class GymUpdateRequest(BaseModel):
    """Body for PUT /api/v1/gyms/{gym_id}."""

    data: GymUpdateData


class GymResponse(BaseModel):
    """A single gym row (basic fields, no Stripe state)."""

    gym_id: UUID
    gym_name: str
    gym_description: str | None
    timezone: str
    # NOT NULL on the gyms row — every rank-enabled gym has one.
    sub_rank_type: SubRankType
    # The gym's uploaded logo (CDN URL); None = no logo uploaded yet.
    logo_url: str | None = None
    # The ThemeService design id this gym brands with (None until chosen).
    theme_design_id: str | None = None


class GymWithRoleResponse(GymResponse):
    """A gym the caller administers, annotated with their role.

    Returned by ``GET /api/v1/gyms/`` — the list of gyms the
    authenticated user owns or admins (``employee_type`` is the
    caller's role for that gym). ``theme_preference`` is the caller's
    own CRM appearance choice for that gym, so the admin app can
    hydrate the theme at login.
    """

    employee_type: EmployeeType
    theme_preference: ThemeMode


class EmployeeThemeUpdateData(BaseModel):
    """Mutable field for PUT .../employees/me/theme.

    Per project convention, update requests separate identity (the
    URL ``gym_id`` + the caller's JWT) from a nested ``data`` model.
    Theme is the only settable field here.
    """

    theme_preference: ThemeMode


class EmployeeThemeUpdateRequest(BaseModel):
    """Body for PUT /api/v1/gyms/{gym_id}/employees/me/theme."""

    data: EmployeeThemeUpdateData


class EmployeeThemeResponse(BaseModel):
    """The caller's saved theme for a gym (echoed back on update)."""

    gym_id: UUID
    theme_preference: ThemeMode


class GymThemeUpdateData(BaseModel):
    """Mutable field for PUT .../theme.

    Per project convention, update requests separate identity (the
    URL ``gym_id``) from a nested ``data`` model. ``theme_design_id``
    is the one settable field here.
    """

    theme_design_id: str = Field(min_length=1, max_length=255)


class GymThemeUpdateRequest(BaseModel):
    """Body for PUT /api/v1/gyms/{gym_id}/theme."""

    data: GymThemeUpdateData


class GymThemeResponse(BaseModel):
    """The gym's saved ThemeService design id (echoed back on update)."""

    gym_id: UUID
    theme_design_id: str


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
    stripe_onboarding_status: Literal[StripeOnboardingStatus.pending]
    onboarding_url: str
    onboarding_url_expires_at: datetime


class GymStripeAccountSnapshot(BaseModel):
    """Flat projection of the Stripe Account fields we care about.

    The shared output of the canonical mapper in
    ``gyms_status_mapping.py`` — fed both by the status-refresh
    endpoint and the ``account.updated`` webhook.
    """

    status: StripeOnboardingStatus
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    disabled_reason: str | None = None
    requirements_currently_due: list[str] = []


class GymOnboardingStatusResponse(BaseModel):
    """Response for GET /api/v1/gyms/{gym_id}/onboarding."""

    gym_id: UUID
    stripe_onboarding_status: StripeOnboardingStatus
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
