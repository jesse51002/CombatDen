"""EmailRetrySweep — re-attempt outbound email that never got delivered.

An email is claimed as an ``email_log`` row and delivered by a detached
fire-and-forget runner right after the triggering request returns. If the
process dies mid-send, or the mail provider is briefly unreachable, the row is
left ``pending`` (never attempted) or ``failed`` (attempted, provider said no).
This sweep — one step of the twice-daily reconciler run — re-attempts each of
them, which is what turns a provider outage into a delay instead of a staff
member who can never log in.

``held`` rows are deliberately NOT swept. A held row means its kind was absent
from the enabled-kinds set when it was claimed (e.g. member app invites while
the member app is not yet installable). Sweeping them would mean that adding a
kind to the set months later drains the entire backlog at once and mails
everyone who ever joined, about a gym they joined long ago. Releasing held mail
is a deliberate act, never a side effect of turning a flag on.

``sent`` and ``suppressed`` are terminal successes; a ``failed`` row that has
exhausted ``max_attempts`` is no longer retryable and is left alone rather than
retried forever against an address that is not going to start working.
"""

import logging

from src.emails.service.emails_service import EmailsService
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)

SWEEP_NAME = "email_retry"


class EmailRetrySweep:
    """Re-attempt every unsent, still-retryable email."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        emails_service: EmailsService,
        batch_limit: int,
        max_attempts: int,
    ) -> None:
        self._db_pool = db_pool
        self._emails_service = emails_service
        self._batch_limit = batch_limit
        self._max_attempts = max_attempts

    async def run(self) -> SweepResult:
        """Re-send each retryable row; one failure never aborts the sweep."""
        email_ids = await self._emails_service.pending_for_retry(
            limit=self._batch_limit,
            max_attempts=self._max_attempts,
        )
        result = SweepResult(name=SWEEP_NAME, processed=len(email_ids))
        for email_id in email_ids:
            try:
                # send_now is itself idempotent and records its own failures,
                # so a provider error here is already persisted on the row —
                # this except is the belt-and-braces guard for an unexpected
                # crash, not the normal failure path.
                await self._emails_service.send_now(email_id)
                result.changed += 1
            except Exception:
                logger.error(
                    "Email retry failed: email_id=%s",
                    email_id,
                    exc_info=True,
                )
                result.errors += 1
        logger.info(
            "Email retry: processed=%d resent=%d errors=%d",
            result.processed,
            result.changed,
            result.errors,
        )
        return result
