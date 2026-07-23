"""Member-portal reads that no staff-facing service already answers.

Everything else the member portal serves is pure delegation done in the
router (the schedule board, the video feed/rec, sign-ups, rewards, check-in
history, the streak) — this service exists for exactly two things:

1. ``list_members_for_email`` — the portal's ENTRY POINT. No existing service
   answers "which member rows bear this verified email", because no CRM route
   ever needs to: staff always come in holding a ``member_id``. A member's app
   holds only a JWT.
2. ``get_profile`` — projects the CRM's ``MemberBillingDetailResponse`` down
   to the member-appropriate ``MemberPortalProfile``. A field projection, not
   business logic: every number is computed by
   ``MembersBillingDetailService``, so the two surfaces can never disagree.
"""

from uuid import UUID

from sqlalchemy import text

from src.member_portal import SQL_DIR
from src.member_portal.schema.member_portal_schema import (
    MemberPortalIdentity,
    MemberPortalIdentityListResponse,
    MemberPortalProfile,
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
