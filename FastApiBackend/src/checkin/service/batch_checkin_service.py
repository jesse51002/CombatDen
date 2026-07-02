"""Batch staff check-in against a single resolved class occurrence.

Injects the two check-in seams directly (no facade): the
``CheckinClassResolver`` loads + validates the occurrence ONCE (a pure read —
so a 50-member batch resolves it exactly once), then the
``CheckinMemberGate`` runs the per-member gate + write for each member. The
batch resolves once, then loops a de-duped, order-preserving member list.

One bad member never sinks the batch: each member is checked in inside its own
``try``, and any exception becomes a ``failed`` item carrying the error message
instead of aborting the loop. ``resolve`` raising (class missing /
deleted / inactive, or not a real occurrence) is the one case that fails the
whole request — it propagates before any per-member work, and the router maps
it to 404 / 400.
"""

from datetime import date, time
from uuid import UUID

from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinItemResult,
    BatchCheckinItemStatus,
    BatchCheckinResponse,
)
from src.checkin.schema.checkin_schema import (
    CheckinResponse,
    ResolvedClass,
)
from src.checkin.service.checkin_class_resolver import (
    CheckinClassResolver,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate


class BatchCheckinService:
    """Checks many members into one class occurrence.

    Args:
        resolver: Resolves + materializes the occurrence once for the batch.
        member_gate: Runs the per-member gate + write for each member.
    """

    def __init__(
        self,
        resolver: CheckinClassResolver,
        member_gate: CheckinMemberGate,
    ) -> None:
        self._resolver = resolver
        self._member_gate = member_gate

    async def batch_checkin(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
        member_ids: list[UUID],
        is_member: bool,
        ignore_warnings: bool = False,
    ) -> tuple[BatchCheckinResponse, bool]:
        """Resolve the occurrence once, then check each member in.

        Args:
            class_id: The class to check into.
            gym_id: The owning gym (auth-scoped by the router).
            occurrence_date: The local calendar date of the occurrence.
            occurrence_time: The occurrence's ORIGINAL slot time — together
                with ``occurrence_date`` the full occurrence identity (a
                class may occur several times per day).
            member_ids: The members to check in (at least one; de-duped,
                order preserved).
            is_member: Applies to every member. ``False`` (a staff batch)
                records a clean member and holds a warned one as
                ``needs_confirmation``; ``True`` runs the strict kiosk gate per
                member (skipping the uncovered / over-capacity).
            ignore_warnings: Staff override applied to every member — record the
                warned ones anyway. Ignored when ``is_member`` is True.

        Returns:
            ``(response, all_failed)`` — the per-member results plus whether
            every processed member failed (the router maps that to 500).

        Raises:
            ValueError: If the occurrence cannot be resolved (class missing /
                deleted / inactive, gym missing, or not a real, non-cancelled
                occurrence on that exact slot). Raised before any per-member
                work, so the whole request fails (router -> 404 / 400).
        """
        resolved_class = await self._resolver.resolve(
            class_id, gym_id, occurrence_date, occurrence_time
        )

        results: list[BatchCheckinItemResult] = []
        for member_id in self._dedupe(member_ids):
            results.append(
                await self._checkin_one(
                    resolved_class, member_id, is_member, ignore_warnings
                )
            )

        all_failed = bool(results) and all(
            item.status == BatchCheckinItemStatus.failed for item in results
        )

        response = BatchCheckinResponse(
            class_id=class_id,
            occurrence_date=occurrence_date,
            results=results,
        )
        return response, all_failed

    async def _checkin_one(
        self,
        resolved_class: ResolvedClass,
        member_id: UUID,
        is_member: bool,
        ignore_warnings: bool,
    ) -> BatchCheckinItemResult:
        """Check one member in against the resolved occurrence, mapping the
        result to a batch item. An exception becomes a ``failed`` item so a
        single bad member never aborts the batch."""
        try:
            res = await self._member_gate.checkin_member(
                resolved_class, member_id, is_member, ignore_warnings
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
          carried).
        * ``requires_confirmation`` (staff warned, not recorded) ->
          needs_confirmation, ``reason`` = the primary warning's value.
        * skipped (kiosk reject, ``log_id`` None) -> skipped, ``reason`` = the
          skip reason's value.
        * recorded (``log_id`` set, not a repeat) -> checked_in (points + plan
          + item + log_id carried).
        """
        if res.already_checked_in:
            status = BatchCheckinItemStatus.already_checked_in
            reason = None
        elif res.requires_confirmation:
            status = BatchCheckinItemStatus.needs_confirmation
            reason = res.warnings[0].value if res.warnings else None
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
            warnings=res.warnings,
        )

    @staticmethod
    def _dedupe(member_ids: list[UUID]) -> list[UUID]:
        """Drop duplicate member ids, preserving first-seen order.

        A member listed twice produces one result and is processed once
        (``checkin_member`` is idempotent anyway; de-duping keeps the results
        clean and avoids the wasted second gate).
        """
        return list(dict.fromkeys(member_ids))
