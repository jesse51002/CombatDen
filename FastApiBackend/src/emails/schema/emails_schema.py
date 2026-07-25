"""Request / response / payload models for the emails domain.

**A payload carries IDs only — never an email address and never a display
name.** Everything person-shaped is re-resolved from the database at send
time by ``EmailsRecipients``, so a row claimed today and delivered by the
retry sweep tomorrow still goes to the address the gym has NOW, and a stale
``email_log.payload`` can never leak a corrected address back into a send.
``email_log.recipient`` — written at send time — is the audit answer to
"where did it really go".
"""

from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip


class StaffOnboardingEmail(BaseModel):
    """Payload for the transactional staff onboarding nudge."""

    kind: Literal[EmailKind.staff_onboarding]
    gym_id: UUID
    employee_id: UUID
    # Bumped per DELIBERATE resend so the idempotency key differs; 0 is the
    # original automatic send.
    resend_seq: int = 0


class MemberAppInviteEmail(BaseModel):
    """Payload for the marketing member app invite."""

    kind: Literal[EmailKind.member_app_invite]
    gym_id: UUID
    member_id: UUID
    resend_seq: int = 0


EmailPayload = Annotated[
    StaffOnboardingEmail | MemberAppInviteEmail,
    Field(discriminator="kind"),
]
"""Discriminated union of every registered payload, keyed by ``kind``."""


class InviteOutcome(StrEnum):
    """What a create/send flow actually did about the email.

    Returned to the caller so a UI can say "invite sent" vs. "no email on
    file" honestly, instead of implying a send that never happened.
    """

    queued = "queued"
    held = "held"
    skipped_no_email = "skipped_no_email"
    skipped_suppressed = "skipped_suppressed"
    not_requested = "not_requested"


class SendEmailRequest(BaseModel):
    """Body of ``POST /api/v1/emails/send``.

    Deliberately carries NO recipient address: the address is resolved from
    the subject's own row, so this endpoint can never be used to mail an
    arbitrary address from CombatDen's sending domain.
    """

    gym_id: UUID
    kind: EmailKind
    employee_id: UUID | None = None
    member_id: UUID | None = None


class SendEmailResponse(BaseModel):
    """What the manual send endpoint did."""

    outcome: InviteOutcome
    email_id: UUID | None = None


class RenderedEmail(BaseModel):
    """A fully rendered message, ready to hand to the provider."""

    subject: str
    html: str
    text: str


class ResolvedRecipient(BaseModel):
    """The address + gym branding resolved for a payload at send time."""

    email: str
    first_name: str
    gym_name: str
    logo_url: str | None = None
