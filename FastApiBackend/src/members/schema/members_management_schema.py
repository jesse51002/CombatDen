"""Request and response schemas for member management operations."""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, field_validator, model_validator

# ── Create ──────────────────────────────────────────────────────


class MembersManagementCreateRequest(BaseModel):
    """Create a new gym member. Card info is optional."""

    gym_id: UUID
    first_name: str
    last_name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    account_linked_to_id: UUID | None = None
    payment_method_id: str | None = None

    @field_validator("first_name", "last_name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("name cannot be empty")
        return v

    @model_validator(mode="after")
    def _check_linked_account_no_payment(self) -> MembersManagementCreateRequest:
        if self.account_linked_to_id is not None and self.payment_method_id is not None:
            raise ValueError("Linked accounts cannot have a payment method")
        return self


# ── Update (personal info) ──────────────────────────────────────


class MembersManagementUpdateRequest(BaseModel):
    """Update a member's personal information. All fields optional."""

    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    account_linked_to_id: UUID | None = None

    @field_validator("first_name", "last_name")
    @classmethod
    def _check_name(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("name cannot be empty")
        return v


# ── Update Card ─────────────────────────────────────────────────


class MembersManagementUpdateCardRequest(BaseModel):
    """Update a member's payment card. Overwrites DB and Stripe."""

    payment_method_id: str


# ── Response ────────────────────────────────────────────────────


class MembersManagementResponse(BaseModel):
    """Shared response for create, update, and update card."""

    crm_user_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    account_linked_to_id: UUID | None = None
    stripe_customer_id: str | None = None
    stripe_payment_method_id: str | None = None
    card_brand: str | None = None
    card_last_four: str | None = None
    card_exp_month: int | None = None
    card_exp_year: int | None = None
