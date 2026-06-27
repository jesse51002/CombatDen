"""Custom exceptions for the memberships domain."""

from __future__ import annotations

from datetime import date
from uuid import UUID


class MembershipStartReplayError(Exception):
    """A retried one-time/trial start was detected as an idempotent replay.

    ``_crm_insert`` stamps a deterministic per-row idempotency key on the real
    start's one-time/trial pending rows; the INSERT's
    ``ON CONFLICT (idempotency_key) DO NOTHING`` drops a retry's duplicate rows
    because the original (completed) start already inserted them. The resulting
    ``RETURNING`` shortfall is detected and surfaced as this error so Phase B is
    NOT re-run — the original rows, their discounts, and their charge stand
    untouched and nothing is duplicated. The router maps it to HTTP 409 (a
    retryable conflict), never a 5xx. (The same shortfall would also arise if
    two requested rows collapsed onto one ``(member_id, price_id)`` key, but the
    request dedup makes that impossible.)
    """

    def __init__(self, *, requested: int, returned: int) -> None:
        self.requested = requested
        self.returned = returned
        super().__init__(
            f"member_memberships insert returned {returned} rows for "
            f"{requested} requested — a duplicate-suppressed idempotent start "
            "replay (one-time/trial rows already exist for this request's "
            "idempotency key). The original memberships stand; nothing was "
            "re-inserted, re-discounted, or re-charged.",
        )


class PartialCancelError(Exception):
    """A multi-payer cancel failed mid-batch — some payers were cancelled, one
    was not.

    A member's memberships can be funded by several payers; ``cancel`` commits
    each payer's ``cancel_date`` only AFTER that payer's Stripe converge
    confirms, processing payers one at a time. If a later payer's converge
    fails (raises or does not confirm), its own ``cancel_date``s are reverted by
    ``sync_or_revert`` — but the payers already converged stay cancelled (their
    Stripe lines are gone, re-billing them would be wrong). So the batch is in a
    partial state with no single clean rollback.

    This error surfaces exactly that state: ``succeeded`` is the
    ``item_id -> cancel_date`` map of every item whose payer fully converged
    before the failure; ``failed_payer_id`` / ``failed_item_ids`` name the payer
    whose converge failed (those items were reverted to un-cancelled). ``cause``
    is the underlying converge failure. The router logs the partial map and
    returns an error so the caller can re-issue the cancel for the failed payer's
    items only (the same idempotency key re-derives the failed payer's sub-key).
    """

    def __init__(
        self,
        *,
        succeeded: dict[UUID, date],
        failed_payer_id: UUID,
        failed_item_ids: list[UUID],
        cause: Exception,
    ) -> None:
        self.succeeded = succeeded
        self.failed_payer_id = failed_payer_id
        self.failed_item_ids = failed_item_ids
        self.cause = cause
        succeeded_ids = sorted(str(i) for i in succeeded)
        failed_ids = sorted(str(i) for i in failed_item_ids)
        super().__init__(
            f"Cancel partially applied: payer {failed_payer_id}'s converge "
            f"failed ({cause}); its items {failed_ids} were reverted, but "
            f"already-converged items {succeeded_ids} stay cancelled. Re-issue "
            f"the cancel for the failed payer's items.",
        )
