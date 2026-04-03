"""Service for fetching member detail data."""

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.member_details_schema import (
    MemberDetailResponse,
    PersonalInfo,
    Retention,
)
from src.members.service.member_details.member_details_membership_grouper import (
    MemberDetailsMembershipGrouper,
)
from src.members.service.member_details.member_details_pricing_bridge import (
    MemberDetailsPricingBridge,
)
from src.members.service.member_details.member_details_supplementary import (
    MemberDetailsSupplementary,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class MemberService:
    """Service for member detail operations.

    Orchestrates sub-services to fetch, price, group, and
    assemble the full member detail response.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool
        self._supplementary = MemberDetailsSupplementary(db_pool)
        self._pricing_bridge = MemberDetailsPricingBridge()
        self._grouper = MemberDetailsMembershipGrouper()

    async def get_member_details(
        self,
        crm_user_id: UUID,
    ) -> MemberDetailResponse:
        """Return full details for a single member and their family.

        Args:
            crm_user_id: The member's CRM user ID.

        Returns:
            MemberDetailResponse with all family memberships
            and supplementary data.

        Raises:
            ValueError: If no profile found for the member.
        """
        rows = await self._fetch_family_rows(crm_user_id)

        if not rows:
            raise ValueError(f"No profile found for crm_user_id={crm_user_id}")

        target_row = _find_target_profile(rows, crm_user_id)
        gym_id = target_row["gym_id"]

        await self._supplementary.fetch_all(gym_id, crm_user_id)

        family_ids = {row["crm_user_id"] for row in rows}
        membership_rows = [r for r in rows if r["plan_id"] is not None]

        pricing_result = self._pricing_bridge.calculate_prices(
            membership_rows,
            self._supplementary.discounts_dict,
        )

        all_grouped = self._grouper.group_by_plan(
            membership_rows,
            pricing_result,
            self._supplementary,
        )

        linked_to_id = target_row["account_linked_to_id"]
        if linked_to_id is not None:
            grouped = self._grouper.filter_plans_for_member(
                all_grouped,
                crm_user_id,
            )
        else:
            grouped = all_grouped

        overview, linked_to_account = self._grouper.build_membership_overview(
            linked_to_id,
            pricing_result.active_total,
            pricing_result.frozen_total,
            pricing_result.has_trial,
            pricing_result.has_cancelled,
            pricing_result.paying_count,
            self._supplementary,
        )

        linked_accounts = self._supplementary.get_family_profiles(
            family_ids,
            crm_user_id,
        )

        return self._build_response(
            crm_user_id=crm_user_id,
            gym_id=gym_id,
            target_row=target_row,
            membership_rows=membership_rows,
            grouped=grouped,
            overview=overview,
            linked_to_account=linked_to_account,
            linked_accounts=linked_accounts,
        )

    async def _fetch_family_rows(
        self,
        crm_user_id: UUID,
    ) -> list:
        """Execute the family group query.

        Args:
            crm_user_id: The member's CRM user ID.

        Returns:
            List of row mappings for the entire family.
        """
        sql = load_sql(SQL_DIR / "member_details.sql")
        params = {"crm_user_id": str(crm_user_id)}

        async for session in self._db_pool.session():
            result = await session.execute(text(sql), params)
            return result.mappings().all()

        return []

    def _build_response(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        target_row: dict,
        membership_rows: list,
        grouped: list,
        overview: str,
        linked_to_account: UUID | None,
        linked_accounts: list,
    ) -> MemberDetailResponse:
        """Assemble the final MemberDetailResponse.

        Args:
            crm_user_id: The queried user's ID.
            gym_id: The gym ID.
            target_row: The queried user's profile row.
            membership_rows: All family membership rows.
            grouped: Grouped MembershipInfo list.
            overview: Membership overview string.
            linked_to_account: Primary account ID or None.
            linked_accounts: LinkedAccount list.

        Returns:
            Fully assembled MemberDetailResponse.
        """
        return MemberDetailResponse(
            crm_user_id=crm_user_id,
            gym_id=gym_id,
            first_name=target_row["first_name"],
            last_name=target_row["last_name"],
            photo_url=target_row["photo_url"],
            account_status=_derive_account_status(
                membership_rows,
                crm_user_id,
            ),
            membership_overview=overview,
            linked_to_account=linked_to_account,
            total_membership_count=len(membership_rows),
            personal_info=PersonalInfo(
                phone=target_row["phone"],
                email=target_row["email"],
                address=target_row["address"],
                emergency_contact_name=(target_row["emergency_contact_name"]),
                emergency_contact_phone=(target_row["emergency_contact_phone"]),
                emergency_contact_email=(target_row["emergency_contact_email"]),
            ),
            linked_accounts=linked_accounts,
            memberships=grouped,
            retention=Retention(
                last_class=target_row["last_class"],
                class_streak_weeks=0,
                points_balance=(target_row["points_balance"] or 0),
                videos_watched=0,
            ),
            recently_redeemed_rewards=(self._supplementary.redeemed_rewards),
            payment_history=(self._supplementary.payment_history),
        )


def _find_target_profile(rows: list, crm_user_id: UUID) -> dict:
    """Find the row belonging to the queried user.

    Args:
        rows: All query result rows.
        crm_user_id: The queried user's ID.

    Returns:
        The first row matching the queried user.

    Raises:
        ValueError: If no matching row is found.
    """
    for row in rows:
        if row["crm_user_id"] == crm_user_id:
            return row
    raise ValueError(f"No profile found for crm_user_id={crm_user_id}")


def _derive_account_status(
    membership_rows: list,
    crm_user_id: UUID,
) -> str | None:
    """Derive the account status from the user's memberships.

    Args:
        membership_rows: All membership rows in the family.
        crm_user_id: The queried user's ID.

    Returns:
        The status of the user's first membership, or None.
    """
    for row in membership_rows:
        if row["crm_user_id"] == crm_user_id:
            return row["membership_status"]
    return None
