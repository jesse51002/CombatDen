"""Custom exceptions for the memberships domain."""

from __future__ import annotations

from datetime import date
from uuid import UUID


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
