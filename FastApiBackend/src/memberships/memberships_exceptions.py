"""Custom exceptions for the memberships domain."""

from __future__ import annotations

from datetime import date
from uuid import UUID


class MembershipStartReplayError(Exception):
    """A retried start was detected as an idempotent replay.

    ``_crm_insert`` stamps a deterministic per-row idempotency key on EVERY one
    of the real start's pending rows — one-time, trial AND recurring; the
    INSERT's ``ON CONFLICT (idempotency_key) DO NOTHING`` drops a retry's
    duplicate rows because the original start already inserted them. The
    resulting ``RETURNING`` shortfall is detected and surfaced as this error so
    Phase B is NOT re-run — the original rows, their discounts, and their charge
    stand untouched and nothing is duplicated. It covers a MIXED cart too: any
    shortfall, whichever plan types collided, rejects the whole request rather
    than half-applying it (the check runs before the commit, so the rows that
    did insert are rolled back). The router maps it to HTTP 409 (a retryable
    conflict), never a 5xx. (The same shortfall would also arise if two
    requested rows collapsed onto one ``(member_id, price_id)`` key, but the
    request dedup makes that impossible.)
    """

    def __init__(self, *, requested: int, returned: int) -> None:
        self.requested = requested
        self.returned = returned
        super().__init__(
            f"member_memberships insert returned {returned} rows for "
            f"{requested} requested — a duplicate-suppressed idempotent start "
            "replay (membership rows already exist for this request's "
            "idempotency key). The original memberships stand; nothing was "
            "re-inserted, re-discounted, or re-charged.",
        )


class WaiverGateError(Exception):
    """A start was attempted before every required waiver was signed.

    Phase-A start validation requires, for each ``(member, plan)`` in the request,
    that the member has signed a current-enough version of every waiver in the
    plan's ``waiver_ids`` — a version at or above the waiver's re-sign floor (the
    highest version whose ``requires_resign`` is true, so a minor edit does not
    re-block prior signers). ``unsigned`` lists each offending
    ``{member_id, waiver_id, name}`` so the router returns a structured 422 the
    CRM can route straight to signing. This runs BEFORE any Stripe call, so a
    rejected start writes nothing and charges nothing.
    """

    def __init__(self, unsigned: list[dict[str, str]]) -> None:
        self.unsigned = unsigned
        names = ", ".join(sorted({u["name"] for u in unsigned}))
        super().__init__(
            f"Cannot start: {len(unsigned)} required waiver signature(s) "
            f"missing ({names}). Sign the waiver(s) before purchase.",
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
