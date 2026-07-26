"""Unit tests for ``EmailsService`` — the claim half and the deliver half.

Everything below the facade is mocked (log, recipients, renderer,
suppression, provider client, db_pool), so nothing here touches a database
or makes an HTTP call to Resend. What is under test is the policy the facade
owns: which status a claim gets, what the idempotency key is made of, which
rows a send attempt is allowed to touch, and which failures are terminal
versus retryable.
"""

from dataclasses import dataclass
from typing import Any
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest

from src.emails.emails_exceptions import EmailsProviderError
from src.emails.schema.emails_schema import (
    MemberAppInviteEmail,
    RenderedEmail,
    ResolvedRecipient,
    StaffOnboardingEmail,
)
from src.emails.service.emails_log import EmailsLog
from src.emails.service.emails_recipients import EmailsRecipients
from src.emails.service.emails_renderer import EmailsRenderer
from src.emails.service.emails_resend_client import EmailsResendClient
from src.emails.service.emails_service import EmailsService
from src.emails.service.emails_suppression import EmailsSuppression

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind, EmailStatus  # isort: skip

UNSUBSCRIBE_BASE_URL = "https://api.combatden.net"
PROVIDER_MESSAGE_ID = "resend-message-id"

RECIPIENT = ResolvedRecipient(
    email="ada@example.com",
    first_name="Ada",
    gym_name="Iron Fist BJJ",
    logo_url=None,
)

RENDERED = RenderedEmail(subject="Subject", html="<p>Body</p>", text="Body")


@dataclass
class Mocks:
    """The collaborators one ``EmailsService`` was built with."""

    db_pool: MagicMock
    session: AsyncMock
    log: MagicMock
    recipients: MagicMock
    renderer: MagicMock
    suppression: MagicMock | EmailsSuppression
    client: MagicMock


def _build(
    *,
    enabled_kinds: frozenset[EmailKind] = frozenset(EmailKind),
    claimed_id: UUID | None = None,
    row: dict[str, Any] | None = None,
    recipient: ResolvedRecipient | None = RECIPIENT,
    suppressed: bool = False,
    send_error: Exception | None = None,
    suppression: EmailsSuppression | None = None,
) -> tuple[EmailsService, Mocks]:
    """An ``EmailsService`` wired to configurable doubles."""
    log = MagicMock(spec=EmailsLog)
    log.claim = AsyncMock(return_value=claimed_id)
    log.load = AsyncMock(return_value=row)

    recipients = MagicMock(spec=EmailsRecipients)
    # The REAL subject-id extraction: the idempotency key is built from it,
    # so a mocked return value would test the format against a mock.
    recipients.subject_id = EmailsRecipients.subject_id
    recipients.resolve = AsyncMock(return_value=recipient)

    renderer = MagicMock(spec=EmailsRenderer)
    renderer.render = MagicMock(return_value=RENDERED)

    gate: MagicMock | EmailsSuppression = suppression or MagicMock(
        spec=EmailsSuppression
    )
    if suppression is None:
        gate.is_suppressed = AsyncMock(return_value=suppressed)
        gate.mint_token = MagicMock(return_value="signed-token")

    client = MagicMock(spec=EmailsResendClient)
    client.send = AsyncMock(
        return_value=PROVIDER_MESSAGE_ID, side_effect=send_error
    )

    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    db_pool = MagicMock()
    db_pool.session.return_value = session

    service = EmailsService(
        db_pool=db_pool,
        log=log,
        recipients=recipients,
        renderer=renderer,
        suppression=gate,
        client=client,
        enabled_kinds=enabled_kinds,
        unsubscribe_base_url=UNSUBSCRIBE_BASE_URL,
    )
    return service, Mocks(
        db_pool=db_pool,
        session=session,
        log=log,
        recipients=recipients,
        renderer=renderer,
        suppression=gate,
        client=client,
    )


def _staff_payload(
    employee_id: UUID | None = None,
    *,
    gym_id: UUID | None = None,
    resend_seq: int = 0,
) -> StaffOnboardingEmail:
    return StaffOnboardingEmail(
        kind=EmailKind.staff_onboarding,
        gym_id=gym_id or uuid4(),
        employee_id=employee_id or uuid4(),
        resend_seq=resend_seq,
    )


def _member_payload(member_id: UUID | None = None) -> MemberAppInviteEmail:
    return MemberAppInviteEmail(
        kind=EmailKind.member_app_invite,
        gym_id=uuid4(),
        member_id=member_id or uuid4(),
    )


def _log_row(
    *,
    status: EmailStatus,
    kind: EmailKind = EmailKind.staff_onboarding,
) -> dict[str, Any]:
    """One ``email_log`` row as ``EmailsLog.load`` returns it."""
    payload = (
        _staff_payload()
        if kind is EmailKind.staff_onboarding
        else _member_payload()
    )
    data = payload.model_dump(mode="json")
    return {
        "email_id": str(uuid4()),
        "gym_id": data["gym_id"],
        "kind": str(kind),
        "status": str(status),
        "payload": data,
    }


def _claim_status(mocks: Mocks) -> EmailStatus:
    """The ``initial_status`` argument the claim was made with."""
    return mocks.log.claim.await_args.args[4]


def _claim_key(mocks: Mocks) -> str:
    """The idempotency key the claim was made with."""
    return mocks.log.claim.await_args.args[2]


# ── enqueue: the claim half ───────────────────────────────────────


@pytest.mark.parametrize(
    ("enabled", "expected"),
    [(True, EmailStatus.pending), (False, EmailStatus.held)],
    ids=["enabled_kind", "disabled_kind"],
)
@pytest.mark.asyncio
async def test_enqueue_claims_pending_only_for_an_enabled_kind(
    enabled: bool,
    expected: EmailStatus,
) -> None:
    """A disabled kind is still RECORDED, just never sendable.

    ``held`` is what makes "staff asked for this" auditable without the row
    ever becoming work for the retry sweep.
    """
    kind = EmailKind.staff_onboarding
    service, mocks = _build(
        enabled_kinds=frozenset({kind}) if enabled else frozenset(),
        claimed_id=uuid4(),
    )

    await service.enqueue(mocks.session, _staff_payload())

    assert _claim_status(mocks) is expected


@pytest.mark.asyncio
async def test_enqueue_returns_none_when_the_key_was_already_claimed() -> None:
    """No RETURNING row means the send already exists — a double-clicked
    button must resolve to one email, not two."""
    service, mocks = _build(claimed_id=None)

    assert await service.enqueue(mocks.session, _staff_payload()) is None


@pytest.mark.asyncio
async def test_the_idempotency_key_is_kind_subject_and_resend_seq() -> None:
    """The key is what collapses duplicates and what a DELIBERATE resend
    must escape: same seq collides (a no-op), a bumped seq does not."""
    employee_id = uuid4()
    service, mocks = _build(claimed_id=uuid4())

    await service.enqueue(mocks.session, _staff_payload(employee_id))
    original = _claim_key(mocks)

    await service.enqueue(
        mocks.session, _staff_payload(employee_id, resend_seq=1)
    )
    resent = _claim_key(mocks)

    await service.enqueue(
        mocks.session, _staff_payload(employee_id, resend_seq=1)
    )
    repeated = _claim_key(mocks)

    assert original == f"{EmailKind.staff_onboarding}:{employee_id}:0"
    assert resent == f"{EmailKind.staff_onboarding}:{employee_id}:1"
    assert resent != original
    assert repeated == resent


# ── send_now: the deliver half ────────────────────────────────────


@pytest.mark.asyncio
async def test_send_now_delivers_and_marks_the_row_sent() -> None:
    """The happy path the other cases are measured against."""
    email_id = uuid4()
    service, mocks = _build(row=_log_row(status=EmailStatus.pending))

    await service.send_now(email_id)

    mocks.client.send.assert_awaited_once_with(RECIPIENT.email, RENDERED)
    mocks.log.mark_sent.assert_awaited_once_with(
        email_id, PROVIDER_MESSAGE_ID, RECIPIENT.email
    )
    mocks.log.mark_failed.assert_not_awaited()
    mocks.log.mark_terminal.assert_not_awaited()


@pytest.mark.asyncio
async def test_send_now_is_a_no_op_for_a_row_already_sent() -> None:
    """Re-running the sweep over a delivered row must not mail it twice."""
    service, mocks = _build(row=_log_row(status=EmailStatus.sent))

    await service.send_now(uuid4())

    mocks.recipients.resolve.assert_not_awaited()
    mocks.client.send.assert_not_awaited()
    mocks.log.mark_sent.assert_not_awaited()
    mocks.log.mark_failed.assert_not_awaited()
    mocks.log.mark_terminal.assert_not_awaited()


@pytest.mark.asyncio
async def test_send_now_never_releases_a_held_row() -> None:
    """``held`` is terminal BY POLICY, not by the current config.

    The kind is enabled in this service on purpose: that is exactly the
    situation the guarantee exists for. Enabling a kind months later must
    not drain the backlog and mail everyone who ever joined — releasing held
    rows has to be a deliberate act.
    """
    service, mocks = _build(
        enabled_kinds=frozenset(EmailKind),
        row=_log_row(status=EmailStatus.held),
    )

    await service.send_now(uuid4())

    mocks.recipients.resolve.assert_not_awaited()
    mocks.client.send.assert_not_awaited()
    mocks.log.mark_sent.assert_not_awaited()
    mocks.log.mark_failed.assert_not_awaited()
    mocks.log.mark_terminal.assert_not_awaited()


@pytest.mark.asyncio
async def test_no_resolvable_address_is_terminal_suppressed_not_failed() -> (
    None
):
    """Retrying cannot invent an address, so this must never be ``failed``.

    A ``failed`` row is work: the sweep would re-attempt it every cycle
    until the attempt ceiling, for a subject that has no mailbox at all.
    """
    email_id = uuid4()
    service, mocks = _build(
        row=_log_row(status=EmailStatus.pending), recipient=None
    )

    await service.send_now(email_id)

    mocks.log.mark_terminal.assert_awaited_once()
    assert mocks.log.mark_terminal.await_args.args[0] == email_id
    assert mocks.log.mark_terminal.await_args.args[1] is EmailStatus.suppressed
    mocks.log.mark_failed.assert_not_awaited()
    mocks.client.send.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_provider_failure_is_recorded_and_never_propagates() -> None:
    """``send_now`` runs detached, so raising would crash a background task
    and lose the failure instead of leaving a retryable row behind."""
    email_id = uuid4()
    service, mocks = _build(
        row=_log_row(status=EmailStatus.pending),
        send_error=EmailsProviderError("Resend rejected the send (500)"),
    )

    await service.send_now(email_id)

    mocks.log.mark_failed.assert_awaited_once()
    assert mocks.log.mark_failed.await_args.args[0] == email_id
    assert "Resend rejected" in mocks.log.mark_failed.await_args.args[1]
    mocks.log.mark_sent.assert_not_awaited()


@pytest.mark.asyncio
async def test_marketing_without_a_signing_secret_fails_instead_of_sending() -> (
    None
):
    """A pitch with no working opt-out is worse than one that waits.

    Driven through the REAL ``EmailsSuppression`` with an empty secret, so
    what is under test is the actual wiring: ``mint_token`` raises, the row
    is recorded ``failed`` (retryable), and nothing reaches the provider.
    """
    unconfigured_db_pool = MagicMock()
    unconfigured_session = AsyncMock()
    unconfigured_session.__aenter__.return_value = unconfigured_session
    unconfigured_session.__aexit__.return_value = None
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = None
    unconfigured_session.execute = AsyncMock(return_value=result)
    unconfigured_db_pool.session.return_value = unconfigured_session

    email_id = uuid4()
    service, mocks = _build(
        row=_log_row(
            status=EmailStatus.pending, kind=EmailKind.member_app_invite
        ),
        suppression=EmailsSuppression(
            db_pool=unconfigured_db_pool, unsubscribe_secret=""
        ),
    )

    await service.send_now(email_id)

    mocks.renderer.render.assert_not_called()
    mocks.client.send.assert_not_awaited()
    mocks.log.mark_sent.assert_not_awaited()
    mocks.log.mark_failed.assert_awaited_once()
    assert (
        "EMAIL_UNSUBSCRIBE_SECRET"
        in mocks.log.mark_failed.await_args.args[1]
    )
