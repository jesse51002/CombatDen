from enum import StrEnum


class EmailKind(StrEnum):
    """Mirrors the Postgres `email_kind` enum.

    Which email CombatDen itself sends. Every value has a registered spec in
    the backend (`FastApiBackend/src/emails/emails_registry.py`) naming its
    category, its template files, and its payload model.

    Adding a kind is five small things, always the same five: a member here, a
    registry entry, a payload model, three template files, and an
    `ALTER TYPE email_kind ADD VALUE` migration. The migration must be applied
    before any code referencing the new value ships — a value added by
    `ALTER TYPE ... ADD VALUE` cannot be referenced by the transaction that
    added it.

    Covers only CombatDen's OWN mail. Supabase Auth's confirmation and
    password-reset mail, and Stripe's card-declined mail (sent from each gym's
    own connected account), are separate channels that never appear here.
    """

    staff_onboarding = "staff_onboarding"
    member_app_invite = "member_app_invite"


class EmailStatus(StrEnum):
    """Mirrors the Postgres `email_status` enum.

    `pending` = claimed but not yet delivered (the reconciler's retry sweep
    picks these up). `sent` and `suppressed` are terminal successes; `failed`
    is retryable until the attempt ceiling.

    `held` is terminal-by-policy and deliberately NOT retryable: the kind was
    absent from `EMAIL_ENABLED_KINDS` at claim time. The row records that staff
    asked, but the sweep skips it forever — otherwise enabling a kind months
    later would drain the whole backlog at once.
    """

    pending = "pending"
    sent = "sent"
    failed = "failed"
    suppressed = "suppressed"
    held = "held"


class EmailSuppressionScope(StrEnum):
    """Mirrors the Postgres `email_suppression_scope` enum.

    How far a suppression reaches. `marketing` is an unsubscribe: it blocks
    marketing kinds only, so opting out of a pitch never costs someone the link
    that gets them into the product. `all` is a hard bounce or explicit block —
    nothing is sent, transactional included, because retrying a dead address is
    what damages a sending domain's reputation.

    Pairs with `EmailCategory` in the backend registry, which is the property
    of a KIND rather than of an address and therefore lives in code, not here.
    """

    marketing = "marketing"
    all = "all"
