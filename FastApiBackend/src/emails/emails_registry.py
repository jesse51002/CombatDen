"""The extension point of the emails domain: one spec per email kind.

**Adding a kind is always the same five things, in this order:**

1. one member on ``EmailKind`` (``Database/python_data/schema/email.py``);
2. one ``ALTER TYPE email_kind ADD VALUE '<kind>'`` migration, APPLIED before
   any code referencing the value ships (a value added by ``ALTER TYPE ...
   ADD VALUE`` cannot be referenced by the transaction that added it);
3. one payload model in ``src/emails/schema/emails_schema.py``, added to the
   ``EmailPayload`` discriminated union — IDs only, never an address;
4. three template files in ``src/emails/templates/``:
   ``<template>.subject.txt``, ``<template>.html``, ``<template>.txt``;
5. one ``SPECS`` entry here.

Nothing else in the domain branches on kind: the log, the renderer, the
suppression check, the client, and the runner all read the spec. That is the
whole point of this file — a new kind never edits a service.

``EmailCategory`` is a property of a KIND, not of an address, so it lives in
code and is deliberately NOT a database enum (unlike
``EmailSuppressionScope``, which describes what an ADDRESS opted out of).
The pairing is asymmetric on purpose: a ``marketing`` kind is blocked by a
``marketing`` OR an ``all`` suppression, a ``transactional`` kind only by
``all`` — opting out of a pitch must never cost someone the link that gets
them into the product.
"""

from dataclasses import dataclass
from enum import StrEnum

from src.emails.schema.emails_schema import (
    MemberAppInviteEmail,
    StaffOnboardingEmail,
)

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip


class EmailCategory(StrEnum):
    """How far a suppression reaches for this kind.

    ``transactional`` carries access (a login link, an account action) and is
    blocked only by an ``all`` suppression. ``marketing`` is a pitch with a
    call to action, is blocked by ``marketing`` or ``all``, and MUST carry an
    unsubscribe link in its templates.
    """

    transactional = "transactional"
    marketing = "marketing"


@dataclass(frozen=True)
class EmailKindSpec:
    """Everything the domain needs to know about one email kind."""

    category: EmailCategory
    # Template BASENAME — the renderer appends .subject.txt / .html / .txt.
    template: str
    # The payload model this kind's email_log.payload validates against.
    payload: type


SPECS: dict[EmailKind, EmailKindSpec] = {
    EmailKind.staff_onboarding: EmailKindSpec(
        category=EmailCategory.transactional,
        template="staff_onboarding",
        payload=StaffOnboardingEmail,
    ),
    EmailKind.member_app_invite: EmailKindSpec(
        category=EmailCategory.marketing,
        template="member_app_invite",
        payload=MemberAppInviteEmail,
    ),
}
