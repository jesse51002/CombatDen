"""Pydantic models for the members domain (member shell CRUD).

List, counts, and detail schemas are membership-derived and live in
members_crm_members_list_schema and members_billing_schema.
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class MemberCreateRequest(BaseModel):
    """Body for POST /api/v1/members/."""

    gym_id: UUID
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr | None = None
    user_id: UUID | None = None
    current_rank_id: UUID | None = None
    # Contact / profile columns (client-editable; written by the backend's
    # privileged connection, not the authenticated role). NULL for
    # engagement-only members with no contact info on file.
    phone: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: EmailStr | None = None
    photo_url: str | None = None
    # Optional card to attach at creation. The Stripe customer is always
    # created (see MembersManagementCreate.create_member); when this is set the
    # payment method is attached as the customer's default at the same time.
    payment_method_id: str | None = None


class MemberUpdateData(BaseModel):
    """Mutable fields on a member row."""

    first_name: str | None = None
    last_name: str | None = None
    email: EmailStr | None = None
    current_rank_id: UUID | None = None
    phone: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: EmailStr | None = None
    photo_url: str | None = None


class MemberUpdateRequest(BaseModel):
    """Body for PUT /api/v1/members/{member_id}."""

    data: MemberUpdateData


class MemberResponse(BaseModel):
    """Bare member row (used by create / update endpoints)."""

    member_id: UUID
    gym_id: UUID
    user_id: UUID | None
    first_name: str
    last_name: str
    email: str | None
    points_balance: int
    last_class: datetime | None
    current_rank_id: UUID | None
    created_at: datetime
    phone: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    photo_url: str | None = None
