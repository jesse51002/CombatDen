"""Facade for checking a member into a class with automatic plan selection.

``CheckinService`` composes the two reusable check-in seams:

* ``CheckinOccurrenceResolver.resolve_occurrence`` turns
  ``(class_id, gym_id, occurrence_date)`` into an ``OccurrenceContext`` (load +
  validate via the canonical ``ClassesExpander`` + lazy-materialize the
  ``class_history`` row). This is the one-way ``checkin -> classes`` dependency.
* ``CheckinMemberGate.checkin_member`` runs the per-member gate + write against a
  resolved occurrence, so a batch can resolve once then loop over members.

The facade exposes ``checkin`` (resolve + check one member in), plus the two
seams (``resolve_occurrence`` / ``checkin_member``) so the batch service can
resolve the occurrence once and loop the per-member gate over many members.
"""

from datetime import date
from uuid import UUID

from src.checkin.schema.checkin_schema import (
    CheckinRequest,
    CheckinResponse,
    OccurrenceContext,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_occurrence_resolver import (
    CheckinOccurrenceResolver,
)


class CheckinService:
    """Checks a member into a class, selecting the best membership plan.

    Args:
        resolver: Resolves + materializes a single class occurrence.
        member_gate: Gates + writes one member against a resolved occurrence.
    """

    def __init__(
        self,
        resolver: CheckinOccurrenceResolver,
        member_gate: CheckinMemberGate,
    ) -> None:
        self._resolver = resolver
        self._member_gate = member_gate

    async def checkin(self, request: CheckinRequest) -> CheckinResponse:
        """Resolve the occurrence, then check the member in.

        Args:
            request: member / gym / class identifiers, the occurrence date, and
                the ``is_member`` flag (kiosk strict gate vs staff always-record).

        Returns:
            The check-in result (recorded, idempotent repeat, or — for a
            rejected kiosk check-in — skipped).

        Raises:
            ValueError: If the class is missing / deleted / inactive, or the
                date is not a real, non-cancelled occurrence (mapped to
                404 / 400 by the router).
        """
        ctx = await self._resolver.resolve_occurrence(
            request.class_id, request.gym_id, request.occurrence_date
        )
        return await self._member_gate.checkin_member(
            ctx, request.member_id, request.is_member
        )

    async def resolve_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> OccurrenceContext:
        """Resolve + materialize a single class occurrence (batch seam).

        Raises:
            ValueError: If the class does not exist / is deleted / is inactive,
                the gym is missing, or no real non-cancelled occurrence lands on
                ``occurrence_date``.
        """
        return await self._resolver.resolve_occurrence(
            class_id, gym_id, occurrence_date
        )

    async def checkin_member(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        is_member: bool = False,
    ) -> CheckinResponse:
        """Gate + write one member against a resolved occurrence (batch seam).

        Args:
            ctx: The resolved occurrence (from ``resolve_occurrence``).
            member_id: The member checking in.
            is_member: ``True`` for the kiosk strict gate (reject when
                uncovered / full); ``False`` (default) for a staff check-in
                (always record, gate conditions become warnings, NULL
                attribution when the member has no membership).

        Returns:
            The check-in result (recorded, idempotent repeat, or — for a
            rejected kiosk check-in — skipped).
        """
        return await self._member_gate.checkin_member(
            ctx, member_id, is_member
        )
