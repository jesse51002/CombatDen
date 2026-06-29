"""Batch staff check-in against a single resolved class occurrence.

Reuses the Phase-4 seams in ``ClassesCheckinService``: ``resolve_occurrence``
loads + validates + materializes the ``class_history`` row ONCE (so a 50-member
batch creates exactly one occurrence row), then ``checkin_member`` runs the
per-member gate + write for each member. The batch resolves once, then loops a
de-duped, order-preserving member list.

One bad member never sinks the batch: each member is checked in inside its own
``try``, and any exception becomes a ``failed`` item carrying the error message
instead of aborting the loop. ``resolve_occurrence`` raising (class missing /
deleted / inactive, or not a real occurrence) is the one case that fails the
whole request — it propagates before any per-member work, and the router maps
it to 404 / 400.
"""

from datetime import date
from uuid import UUID

from src.classes.schema.classes_batch_checkin_schema import (
    BatchCheckinItemResult,
    BatchCheckinItemStatus,
    BatchCheckinResponse,
)
from src.classes.schema.classes_schema import (
    CheckinResponse,
    OccurrenceContext,
)
from src.classes.service.checkin.classes_checkin_service import (
    ClassesCheckinService,
)


class ClassesBatchCheckinService:
    """Checks many members into one class occurrence.

    Args:
        checkin_service: The Phase-4 single-member check-in service. Its
            ``resolve_occurrence`` seam materializes the occurrence once and
            ``checkin_member`` runs the per-member gate + write.
    """

    def __init__(self, checkin_service: ClassesCheckinService) -> None:
        self._checkin_service = checkin_service

    async def batch_checkin(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        member_ids: list[UUID],
        allow_override: bool,
    ) -> tuple[BatchCheckinResponse, bool]:
        """Resolve the occurrence once, then check each member in.

        Args:
            class_id: The class to check into (PATH param).
            gym_id: The owning gym (auth-scoped by the router).
            occurrence_date: The local calendar date of the occurrence (PATH).
            member_ids: The members to check in (at least one; de-duped,
                order preserved).
            allow_override: Force every member past the eligibility,
                punch-card, and room-capacity gates (front-desk coverage).

        Returns:
            ``(response, all_failed)`` — the per-member results plus whether
            every processed member failed (the router maps that to 500).

        Raises:
            ValueError: If the occurrence cannot be resolved (class missing /
                deleted / inactive, gym missing, or not a real, non-cancelled
                occurrence on that date). Raised before any per-member work, so
                the whole request fails (router -> 404 / 400).
        """
        ctx = await self._checkin_service.resolve_occurrence(
            class_id, gym_id, occurrence_date
        )

        results: list[BatchCheckinItemResult] = []
        for member_id in self._dedupe(member_ids):
            results.append(
                await self._checkin_one(ctx, member_id, allow_override)
            )

        all_failed = bool(results) and all(
            item.status == BatchCheckinItemStatus.failed for item in results
        )

        response = BatchCheckinResponse(
            class_id=class_id,
            occurrence_date=occurrence_date,
            class_history_id=ctx.class_history_id,
            results=results,
        )
        return response, all_failed

    async def _checkin_one(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        allow_override: bool,
    ) -> BatchCheckinItemResult:
        """Check one member in against the resolved occurrence, mapping the
        result to a batch item. An exception becomes a ``failed`` item so a
        single bad member never aborts the batch."""
        try:
            res = await self._checkin_service.checkin_member(
                ctx, member_id, allow_override
            )
        except Exception as exc:  # noqa: BLE001 — isolate one member's failure
            return BatchCheckinItemResult(
                member_id=member_id,
                status=BatchCheckinItemStatus.failed,
                reason=str(exc),
            )
        return self._map_result(member_id, res)

    @staticmethod
    def _map_result(
        member_id: UUID, res: CheckinResponse
    ) -> BatchCheckinItemResult:
        """Map a single-member ``CheckinResponse`` to a batch item.

        * ``already_checked_in`` -> already_checked_in (log_id / plan / item
          carried, points 0).
        * recorded (``log_id`` set, not a repeat) -> checked_in (points + plan
          + item + log_id carried).
        * skipped (``log_id`` is None) -> skipped, ``reason`` = the skip
          reason's value.
        """
        if res.already_checked_in:
            status = BatchCheckinItemStatus.already_checked_in
            reason = None
        elif res.log_id is None:
            status = BatchCheckinItemStatus.skipped
            reason = res.skip_reason.value if res.skip_reason else None
        else:
            status = BatchCheckinItemStatus.checked_in
            reason = None
        return BatchCheckinItemResult(
            member_id=member_id,
            status=status,
            reason=reason,
            points_awarded=res.points_awarded,
            chosen_plan_id=res.chosen_plan_id,
            chosen_item_id=res.chosen_item_id,
            log_id=res.log_id,
        )

    @staticmethod
    def _dedupe(member_ids: list[UUID]) -> list[UUID]:
        """Drop duplicate member ids, preserving first-seen order.

        A member listed twice produces one result and is processed once
        (``checkin_member`` is idempotent anyway; de-duping keeps the results
        clean and avoids the wasted second gate).
        """
        return list(dict.fromkeys(member_ids))
