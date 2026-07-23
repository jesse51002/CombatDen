"""Member-portal reads that no staff-facing service already answers.

Everything else the member portal serves is pure delegation done in the
router (the schedule board, the video feed/rec, sign-ups, rewards, check-in
history, the streak) — this service exists for exactly three reads with no
existing owner:

1. ``list_members_for_email`` — the portal's ENTRY POINT. No existing service
   answers "which member rows bear this verified email", because no CRM route
   ever needs to: staff always come in holding a ``member_id``. A member's app
   holds only a JWT.
2. ``get_profile`` — projects the CRM's ``MemberBillingDetailResponse`` down
   to the member-appropriate ``MemberPortalProfile``. A field projection, not
   business logic: every number is computed by
   ``MembersBillingDetailService``, so the two surfaces can never disagree.
3. ``get_rank_progress`` — the profile graph's data: the member's progress
   toward their next rank over time, walked from their ``member_activities``.
   The per-step ``classes_needed`` denominator uses the SAME derivation as the
   profile's rank block, so the graph and the rank card can never disagree.
"""

import math
from uuid import UUID

from schema.gym_rank import SubRankType, effective_sub_count
from schema.member_activity import MemberActivityType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.member_portal import SQL_DIR
from src.member_portal.schema.member_portal_schema import (
    MemberPortalIdentity,
    MemberPortalIdentityListResponse,
    MemberPortalProfile,
    MemberRankProgressResponse,
    RankProgressPoint,
)
from src.members.service.member_details.members_billing_detail_service import (
    MembersBillingDetailService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class MemberPortalService:
    """Member-portal identity resolution + the member's own profile read.

    Args:
        db_pool: Injected database connection pool.
        billing_detail_service: The CRM member-detail service the profile is
            projected from (never re-derived here).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        billing_detail_service: MembersBillingDetailService,
    ) -> None:
        self._db_pool = db_pool
        self._billing_detail_service = billing_detail_service

    async def list_members_for_email(
        self,
        email: str,
        caller_id: str,
    ) -> MemberPortalIdentityListResponse:
        """Return every member row bearing ``email``, across gyms.

        A parent's verified address legitimately matches several member rows
        (``members.email`` has no uniqueness constraint — families share an
        inbox), so this is always a list. An email that matches nothing
        returns an empty list, not an error: a signed-in person who is
        nobody's member is a valid, empty state.

        Args:
            email: The caller's lowercased, already-verified email claim.
            caller_id: The JWT ``sub`` — the confirmed-account ``EXISTS`` pins
                on it, so the query proves the CALLER's own account is
                confirmed, not merely that some confirmed account holds this
                email.

        Returns:
            The caller's member rows, each annotated with its gym.
        """
        sql = load_sql(SQL_DIR / "member_portal_list_members.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"email": email, "caller_id": caller_id}
                    )
                )
                .mappings()
                .fetchall()
            )

        return MemberPortalIdentityListResponse(
            members=[MemberPortalIdentity(**dict(row)) for row in rows],
        )

    async def get_profile(self, member_id: UUID) -> MemberPortalProfile:
        """Project the member's CRM detail down to the portal profile.

        Args:
            member_id: The member, already proven to BE the caller.

        Returns:
            The member-appropriate profile block.

        Raises:
            ValueError: If no billing profile exists for the member.
        """
        detail = await self._billing_detail_service.get_member_billing_detail(
            member_id,
        )
        return MemberPortalProfile(
            member_id=detail.member_id,
            gym_id=detail.gym_id,
            first_name=detail.first_name,
            last_name=detail.last_name,
            photo_url=detail.photo_url,
            personal_info=detail.personal_info,
            retention=detail.retention,
            rank=detail.rank,
            memberships=detail.memberships,
            recently_redeemed_rewards=detail.recently_redeemed_rewards,
            pending_redemptions=detail.pending_redemptions,
        )

    async def get_rank_progress(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> MemberRankProgressResponse:
        """Build the member's rank-progress series from their activity stream.

        Walks the member's ``rank_changed`` + ``class_attended`` activities
        chronologically: a ``rank_changed`` (a promotion) resets the running
        count to 0, a ``class_attended`` increments it by one, capped at
        ``classes_needed`` — the member's CURRENT per-step rank threshold,
        derived exactly like the profile's rank block. Historical threshold
        changes are approximated by today's value — acceptable for a graph.

        Returns an empty series (a valid state) when the member holds no rank
        or the gym has ranks disabled.

        Args:
            member_id: The member, already proven to BE the caller.
            gym_id: The member's gym (already gate-verified).

        Returns:
            The member's rank-progress points, oldest first.
        """
        sql = load_sql(SQL_DIR / "member_portal_rank_progress.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(member_id),
                            "gym_id": str(gym_id),
                        },
                    )
                )
                .mappings()
                .fetchall()
            )

        if not rows:
            return MemberRankProgressResponse(points=[])

        context = rows[0]
        if context["current_rank_id"] is None or not context["is_rank_enabled"]:
            return MemberRankProgressResponse(points=[])

        classes_needed = self._classes_needed(context)
        points = self._walk_rank_activities(rows, classes_needed)
        return MemberRankProgressResponse(points=points)

    @staticmethod
    def _classes_needed(context: dict) -> int:
        """Classes to the member's next rank — the per-step threshold.

        The same derivation the profile's rank block uses
        (``MembersBillingDetailService._build_rank``): an even split of
        ``classes_to_next_major`` across the gym's effective sub-positions,
        else the full major threshold when the rank has none.
        """
        sub_rank_type = SubRankType(context["sub_rank_type"])
        effective_count = effective_sub_count(
            sub_rank_type, context["sub_rank_count"] or 0
        )
        classes_to_next_major = context["classes_to_next_major"]
        if effective_count > 0:
            return math.ceil(classes_to_next_major / effective_count)
        return classes_to_next_major

    @staticmethod
    def _walk_rank_activities(
        rows: list,
        classes_needed: int,
    ) -> list[RankProgressPoint]:
        """Walk the chronological activity rows into progress points.

        One point per activity event: a ``rank_changed`` resets the counter to
        0, a ``class_attended`` increments it by one capped at
        ``classes_needed``. The single context-only row of a member with NO
        activities (NULL ``activity_type``) is skipped.
        """
        points: list[RankProgressPoint] = []
        count = 0
        for row in rows:
            activity_type = row["activity_type"]
            if activity_type is None:
                continue
            if activity_type == MemberActivityType.rank_changed:
                count = 0
            else:
                count = min(count + 1, classes_needed)
            points.append(
                RankProgressPoint(
                    date=row["activity_date"],
                    classes_into_rank=count,
                    classes_needed=classes_needed,
                )
            )
        return points
