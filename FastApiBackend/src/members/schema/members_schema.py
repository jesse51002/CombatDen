"""Pydantic models for the members domain (member shell CRUD).

List, counts, and detail schemas are membership-derived and live in
members_crm_members_list_schema and members_billing_schema.
"""

from datetime import datetime
from typing import Literal
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
    # When False (default), a create with a non-null email is gated against
    # same-identity duplicates (same gym + case/space-insensitive first name,
    # last name, and email): a match raises HTTP 409 with the candidate rows
    # BEFORE any row is written. The client re-sends True to confirm and
    # create anyway. A null-email create is never gated (no reliable identity).
    allow_duplicate: bool = False


class MemberUpdateData(BaseModel):
    """Mutable fields on a member row.

    ``current_rank_id`` is deliberately absent: after creation, a
    member's rank changes ONLY through the ranks domain's
    promote-member / set-member-rank endpoints, which log the
    ``rank_changed`` audit activity the progress anchor depends on.
    A generic update path here would be an unaudited side door.
    """

    first_name: str | None = None
    last_name: str | None = None
    email: EmailStr | None = None
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


class DuplicateMemberMatch(BaseModel):
    """One same-identity member the create duplicate gate already has on file.

    Serialized into the 409 conflict body's ``matches`` list. The field names
    are the wire keys the CRM's own ``DuplicateMemberMatch`` model parses;
    ``member_id`` is a ``str`` (not ``UUID``) so ``model_dump()`` yields a
    JSON-native body byte-identical to the prior ad-hoc dict.
    """

    member_id: str
    first_name: str
    last_name: str
    email: str | None = None
    photo_url: str | None = None


class DuplicateMemberConflict(BaseModel):
    """Typed body of the 409 raised when a same-identity member exists.

    ``code`` is the fixed ``"duplicate_member"`` discriminator the CRM
    switches on (the ``Literal[...] = ...`` constant-discriminator house
    style, as in the Stripe metadata schemas); ``matches`` carries the
    candidate rows so the client can confirm-anyway or use-existing.
    """

    code: Literal["duplicate_member"] = "duplicate_member"
    matches: list[DuplicateMemberMatch]
