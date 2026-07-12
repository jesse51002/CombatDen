"""Pydantic schemas for the employees domain.

Live CRUD for a gym's staff roster (``gym_employees``). Identity is the
``email`` column (lowercase-normalized) — a verified Supabase ``auth.users``
account whose email matches is that person's login; there is no ``user_id``.

``invite_status`` is an API-DERIVED value (from the auth-account join in the
read query), not a stored column, so it lives here rather than mirroring a
Postgres enum. ``EmployeeType`` is reused from the Database package.
"""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, EmailStr, field_validator
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401


class InviteStatus(StrEnum):
    """Whether the employee's email has a usable login.

    Derived at read time from the ``auth.users`` join (mirrors no Postgres
    enum): ``active`` = a verified Supabase account exists for the email;
    ``pending`` = a row was created but has no verified account yet;
    ``none`` = the row has no email (an email-less trainer — instructor
    data, never a login principal).
    """

    active = "active"
    pending = "pending"
    none = "none"


class EmployeeCreateRequest(BaseModel):
    """Create a gym staff member. Plain INSERT — no auth-system interaction.

    ``employee_type`` may not be ``owner`` (the owner row is seeded at gym
    creation, unique per gym). ``email`` is required and lowercased so it
    matches the verified auth account created for the person.
    """

    employee_type: EmployeeType
    first_name: str
    last_name: str
    email: EmailStr
    phone: str | None = None
    employee_public_description: str | None = None

    @field_validator("employee_type")
    @classmethod
    def _reject_owner(cls, v: EmployeeType) -> EmployeeType:
        if v is EmployeeType.owner:
            raise ValueError("Cannot create an owner employee")
        return v

    @field_validator("first_name", "last_name")
    @classmethod
    def _non_empty_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("Name fields cannot be blank")
        return stripped

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str) -> str:
        return v.lower()


class EmployeeUpdateData(BaseModel):
    """Mutable employee fields. All optional — only send what changed.

    ``None`` means "leave unchanged" (this endpoint does not clear a field
    to NULL). ``employee_type`` may never be set to ``owner``.
    """

    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None
    email: EmailStr | None = None
    employee_public_description: str | None = None
    employee_pic_url: str | None = None
    employee_type: EmployeeType | None = None

    @field_validator("employee_type")
    @classmethod
    def _reject_owner(cls, v: EmployeeType | None) -> EmployeeType | None:
        if v is EmployeeType.owner:
            raise ValueError("Cannot set an employee's type to owner")
        return v

    @field_validator("first_name", "last_name")
    @classmethod
    def _non_empty_name(cls, v: str | None) -> str | None:
        if v is None:
            return v
        stripped = v.strip()
        if not stripped:
            raise ValueError("Name fields cannot be blank")
        return stripped

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str | None) -> str | None:
        return v.lower() if v is not None else v


class EmployeeUpdateRequest(BaseModel):
    """Update a gym staff member.

    Identity (``gym_id`` + ``employee_id``) comes from the URL path; the
    body carries only the mutable ``data`` (project update-request
    convention).
    """

    data: EmployeeUpdateData


class EmployeeResponse(BaseModel):
    """A single ``gym_employees`` row plus the derived invite status."""

    employee_id: UUID
    gym_id: UUID
    employee_type: EmployeeType
    first_name: str
    last_name: str
    phone: str | None
    email: str | None
    employee_pic_url: str | None
    employee_public_description: str | None
    created_at: datetime
    invite_status: InviteStatus


class EmployeeListResponse(BaseModel):
    """All non-archived employees of a gym (every type)."""

    employees: list[EmployeeResponse]
