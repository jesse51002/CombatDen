"""Pydantic models for the gyms domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class GymCreateRequest(BaseModel):
    """Body for POST /api/v1/gyms/."""

    gym_name: str = Field(min_length=1)
    gym_description: str | None = None
    timezone: str = "America/Chicago"
    owner_first_name: str = Field(min_length=1)
    owner_last_name: str = Field(min_length=1)
    owner_phone: str | None = None
    owner_email: str | None = None


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
    """A single gym row."""

    gym_id: UUID
    gym_name: str
    gym_description: str | None
    timezone: str


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
    """Response for POST /api/v1/gyms/."""

    gym: GymResponse
    owner: GymEmployeeResponse
