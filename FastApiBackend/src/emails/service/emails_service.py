"""The emails facade: claim a send, then deliver one.

Two halves, deliberately separated by the caller's transaction boundary:

* ``enqueue`` runs INSIDE the caller's transaction (an employee insert, a
  member insert). A rolled-back operation un-sends its email for free.
* ``send_now`` runs AFTER that commit, detached (see ``EmailsRunner``), and
  NEVER raises to the caller — the employee was still created even when the
  mail provider is down. The row it leaves behind is what the reconciler's
  retry sweep picks up.
"""

import logging
from typing import Any
from uuid import UUID

from pydantic import TypeAdapter
from sqlalchemy.ext.asyncio import AsyncSession

from src.emails.emails_registry import SPECS, EmailCategory
from src.emails.schema.emails_schema import (
    EmailPayload,
    InviteOutcome,
)
from src.emails.service.emails_log import EmailsLog
from src.emails.service.emails_recipients import EmailsRecipients
from src.emails.service.emails_renderer import EmailsRenderer
from src.emails.service.emails_resend_client import EmailsResendClient
from src.emails.service.emails_suppression import EmailsSuppression
from src.shared.database import DirectDatabasePool

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind, EmailStatus  # isort: skip

logger = logging.getLogger(__name__)

# The unsubscribe route the minted token is appended to. Joined onto the
# injected public base URL, so the two never drift apart in templates.
UNSUBSCRIBE_PATH = "/api/v1/emails/unsubscribe"

_PAYLOAD_ADAPTER: TypeAdapter[EmailPayload] = TypeAdapter(EmailPayload)


class EmailsService:
    """Claim, then deliver, one of CombatDen's own emails."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        log: EmailsLog,
        recipients: EmailsRecipients,
        renderer: EmailsRenderer,
        suppression: EmailsSuppression,
        client: EmailsResendClient,
        enabled_kinds: frozenset[EmailKind],
        unsubscribe_base_url: str,
    ) -> None:
        self._db_pool = db_pool
        self._log = log
        self._recipients = recipients
        self._renderer = renderer
        self._suppression = suppression
        self._client = client
        # A kind absent from this set is claimed as 'held': the row records
        # that staff asked, but nothing ever sends it — not even the retry
        # sweep. Enabling a kind months later must not drain the backlog and
        # mail everyone who ever joined; releasing held rows is a deliberate
        # act, never a side effect of flipping a flag.
        self._enabled_kinds = enabled_kinds
        self._unsubscribe_base_url = unsubscribe_base_url.rstrip("/")

    async def enqueue(
        self,
        session: AsyncSession,
        payload: EmailPayload,
    ) -> UUID | None:
        """Claim a send inside the CALLER's open transaction.

        The caller commits (or rolls back) as part of its own operation and
        then, after the commit, fires ``EmailsRunner.start(email_id)``.

        Returns:
            The claimed ``email_id``, or None when this exact send was
            already claimed (the idempotency key collided).
        """
        data = payload.model_dump(mode="json")
        subject_id = self._recipients.subject_id(data)
        key = self._idempotency_key(data, subject_id)
        status = self._initial_status(EmailKind(data["kind"]))
        return await self._log.claim(
            session, data, key, subject_id, status
        )

    async def request_send(
        self,
        payload: EmailPayload,
    ) -> tuple[UUID | None, InviteOutcome]:
        """Claim a send from a caller with no transaction of its own.

        The manual-send endpoint's entry point: it opens its own session,
        commits the claim, and reports honestly what happened — including
        the two cases where nothing is claimed at all, so a UI never says
        "invite sent" about an address that does not exist.

        Returns:
            ``(email_id, outcome)``. ``email_id`` is None whenever no row
            was written (no address, suppressed, or already claimed).
        """
        data = payload.model_dump(mode="json")
        kind = EmailKind(data["kind"])
        recipient = await self._recipients.resolve(data)
        if recipient is None:
            return None, InviteOutcome.skipped_no_email

        category = SPECS[kind].category
        if await self._suppression.is_suppressed(
            recipient.email, payload.gym_id, category
        ):
            return None, InviteOutcome.skipped_suppressed

        async with self._db_pool.session() as session:
            email_id = await self.enqueue(session, payload)
            await session.commit()

        if email_id is None:
            return None, InviteOutcome.not_requested
        outcome = (
            InviteOutcome.queued
            if kind in self._enabled_kinds
            else InviteOutcome.held
        )
        return email_id, outcome

    async def pending_for_retry(
        self,
        limit: int,
        max_attempts: int,
    ) -> list[UUID]:
        """The ids the reconciler's retry sweep should re-attempt.

        The sweep talks only to this facade (never to ``EmailsLog``), so the
        retry contract is one method: ids in, ``send_now`` per id. ``held``
        and ``suppressed`` rows are excluded by the query — both are
        terminal by policy.
        """
        rows = await self._log.pending_for_retry(limit, max_attempts)
        return [UUID(str(row["email_id"])) for row in rows]

    async def send_now(self, email_id: UUID) -> None:
        """Deliver one claimed email. NEVER raises to the caller.

        A failure here must not surface: the operation that triggered the
        email already succeeded, and the row records the failure for the
        retry sweep.
        """
        try:
            await self._deliver(email_id)
        except Exception as exc:
            await self._record_failure(email_id, exc)

    async def _deliver(self, email_id: UUID) -> None:
        """The send path proper — resolve, gate, render, send, mark."""
        row = await self._log.load(email_id)
        if row is None:
            logger.error("No email_log row for email_id=%s", email_id)
            return

        status = EmailStatus(row["status"])
        if status in (EmailStatus.sent, EmailStatus.held):
            # 'sent' is done; 'held' is terminal by policy and must never be
            # released as a side effect of a send attempt.
            return

        payload: dict[str, Any] = row["payload"]
        kind = EmailKind(row["kind"])
        gym_id = UUID(str(row["gym_id"]))
        category = SPECS[kind].category

        recipient = await self._recipients.resolve(payload)
        if recipient is None:
            # No address on file (or the employee was archived between the
            # claim and the send). Terminal: retrying cannot invent one.
            await self._log.mark_terminal(
                email_id,
                EmailStatus.suppressed,
                error="No deliverable address for the subject",
            )
            return

        if await self._suppression.is_suppressed(
            recipient.email, gym_id, category
        ):
            await self._log.mark_terminal(
                email_id,
                EmailStatus.suppressed,
                recipient=recipient.email,
                error=f"Address suppressed for {category} mail",
            )
            return

        message = self._renderer.render(
            payload,
            recipient,
            unsubscribe_url=self._unsubscribe_url(
                recipient.email, gym_id, category
            ),
        )
        provider_message_id = await self._client.send(
            recipient.email, message
        )
        await self._log.mark_sent(
            email_id, provider_message_id, recipient.email
        )

    async def _record_failure(self, email_id: UUID, exc: Exception) -> None:
        """Persist a send failure, and never let THAT raise either."""
        logger.error(
            "Email send failed: email_id=%s", email_id, exc_info=exc
        )
        try:
            await self._log.mark_failed(email_id, str(exc)[:1000])
        except Exception:
            logger.error(
                "Could not record email failure: email_id=%s",
                email_id,
                exc_info=True,
            )

    def _unsubscribe_url(
        self,
        email: str,
        gym_id: UUID,
        category: EmailCategory,
    ) -> str | None:
        """The signed unsubscribe link, for marketing kinds only.

        Deliberately NOT guarded against an unconfigured signing secret:
        ``mint_token`` raises, ``send_now`` records that as a failed row, and
        the retry sweep re-attempts it once the secret is set. Do not "fix"
        this by catching the error and sending without a link — a marketing
        email whose opt-out can be forged (or is missing entirely) is worse
        than one that waits for configuration.
        """
        if category is not EmailCategory.marketing:
            return None
        token = self._suppression.mint_token(email, gym_id)
        return (
            f"{self._unsubscribe_base_url}{UNSUBSCRIBE_PATH}?token={token}"
        )

    def _initial_status(self, kind: EmailKind) -> EmailStatus:
        """``pending`` for an enabled kind, ``held`` for a disabled one."""
        return (
            EmailStatus.pending
            if kind in self._enabled_kinds
            else EmailStatus.held
        )

    @staticmethod
    def _idempotency_key(
        payload: dict[str, Any],
        subject_id: UUID | None,
    ) -> str:
        """``<kind>:<subject_id>:<resend_seq>``.

        The whole no-duplicates mechanism: a double-clicked button, a
        retried request, and a re-run sweep all collide on this key. A
        DELIBERATE resend bumps ``resend_seq``, which is what makes it a
        genuinely new send rather than a no-op.
        """
        seq = payload.get("resend_seq", 0)
        return f"{payload['kind']}:{subject_id}:{seq}"

    @staticmethod
    def payload_from_dict(data: dict[str, Any]) -> EmailPayload:
        """Validate a stored ``email_log.payload`` back into its model."""
        return _PAYLOAD_ADAPTER.validate_python(data)
