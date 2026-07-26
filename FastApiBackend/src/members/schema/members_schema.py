"""Pydantic models for the members domain (member shell CRUD).

List, counts, and detail schemas are membership-derived and live in
members_crm_members_list_schema and members_billing_schema.
"""

from datetime import date, datetime
from typing import Final, Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from src.emails.schema.emails_schema import InviteOutcome
from src.members.schema.members_billing_schema import (
    MembersBillingProfileResponse,
)

# Floor for a plausible date of birth. Wide enough that it can never reject a
# real member, tight enough to catch the realistic typo class from the kiosk's
# free-form date entry (a truncated or mistyped year: 0202-06-01, 1066). A
# fixed calendar floor, not a max age, so it needs no policy and never ages.
EARLIEST_DATE_OF_BIRTH: Final[date] = date(1900, 1, 1)


def _validate_date_of_birth(value: date | None) -> date | None:
    """Reject a future or pre-1900 date of birth (-> 422).

    Shared by every schema that accepts a DOB so create and update cannot
    drift. The DB carries the matching CHECK (``date_of_birth_plausible``),
    so a writer that bypasses this model — the seed, an importer, a hand-run
    UPDATE — still cannot store what the API refuses.
    """
    if value is None:
        return value
    today = date.today()
    if value > today:
        raise ValueError(
            f"date_of_birth cannot be in the future (got {value.isoformat()}, "
            f"today is {today.isoformat()})",
        )
    if value < EARLIEST_DATE_OF_BIRTH:
        raise ValueError(
            f"date_of_birth cannot be before "
            f"{EARLIEST_DATE_OF_BIRTH.isoformat()} "
            f"(got {value.isoformat()})",
        )
    return value


class MemberCreateResult(BaseModel):
    """Internal create outcome — the member plus its claimed invite.

    ``email_id`` never reaches a client: the router fires the detached send
    with it and returns ``MemberCreateResponse``. Splitting the two keeps the
    claim next to the row it belongs to while the send happens only after
    that write is committed.
    """

    member: MembersBillingProfileResponse
    invite: InviteOutcome
    email_id: UUID | None = None


class MemberCreateResponse(BaseModel):
    """The created member plus what actually happened to their app invite.

    Staff are asked whether to invite, so they are told the truth: a member
    with no email on file reports ``skipped_no_email``, and a kind that is
    not enabled yet reports ``held`` — never an unqualified success.
    """

    member: MembersBillingProfileResponse
    invite: InviteOutcome


class MemberCreateRequest(BaseModel):
    """Body for POST /api/v1/members/."""

    gym_id: UUID
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr | None = None
    current_rank_id: UUID | None = None
    # Contact / profile columns (client-editable; written by the backend's
    # privileged connection, not the authenticated role). NULL for
    # engagement-only members with no contact info on file.
    phone: str | None = None
    address: str | None = None
    # Optional date of birth (the kiosk signup's optional-details step).
    date_of_birth: date | None = None
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
    # REQUIRED, no default. The CRM's create dialog answers it with
    # "Create & invite" vs "Create without inviting"; the kiosk's
    # self-signup passes True without prompting, since someone joining on
    # the gym's own iPad has already expressed the intent the prompt
    # would ask about. No default, so an older client cannot silently
    # stop inviting anyone — it fails at the schema boundary instead.
    # A member with no email always resolves to skipped_no_email.
    send_invite: bool

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str | None) -> str | None:
        """Normalize email to lowercase (identity normalization).

        A member's email is now identity: a verified auth account whose
        email matches it (compared lowercase) is that person's access, so
        the stored value must be lowercase.
        """
        return v.lower() if v is not None else v

    @field_validator("date_of_birth")
    @classmethod
    def _plausible_date_of_birth(cls, v: date | None) -> date | None:
        """Reject a future or pre-1900 date of birth (see the module helper)."""
        return _validate_date_of_birth(v)


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
    date_of_birth: date | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: EmailStr | None = None
    photo_url: str | None = None

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str | None) -> str | None:
        """Normalize email to lowercase (identity normalization).

        A member's email is now identity: a verified auth account whose
        email matches it (compared lowercase) is that person's access, so
        the stored value must be lowercase.
        """
        return v.lower() if v is not None else v

    @field_validator("date_of_birth")
    @classmethod
    def _plausible_date_of_birth(cls, v: date | None) -> date | None:
        """Reject a future or pre-1900 date of birth (see the module helper).

        This model is the only other way a DOB reaches the column through the
        API, so it needs the same guard as create.
        """
        return _validate_date_of_birth(v)


class MemberUpdateRequest(BaseModel):
    """Body for PUT /api/v1/members/{member_id}."""

    data: MemberUpdateData


class MemberResponse(BaseModel):
    """Bare member row (used by create / update endpoints)."""

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    email: str | None
    points_balance: int
    last_class: datetime | None
    current_rank_id: UUID | None
    created_at: datetime
    phone: str | None = None
    address: str | None = None
    date_of_birth: date | None = None
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

