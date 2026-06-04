"""Service for fetching full member billing detail data."""

from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.classes.service.classes_streak_service import ClassesStreakService
from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    BillingCardOnFile,
    BillingPersonalInfo,
    BillingRank,
    BillingRetention,
    MemberBillingDetailResponse,
)
from src.members.service.member_details.members_billing_grouper import (
    MembersBillingGrouper,
)
from src.members.service.member_details.members_billing_supplementary import (
    MembersBillingSupplementary,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_DETAILS_SQL = SQL_DIR / "member_details"


class MembersBillingDetailService:
    """Service for member billing detail operations.

    Orchestrates supplementary queries and assembles the full
    MemberBillingDetailResponse used by the CRM member detail screen.

    Args:
        db_pool: Injected database connection pool.
        streak_service: Injected streak calculation service.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        streak_service: ClassesStreakService,
    ) -> None:
        self._db_pool = db_pool
        self._supplementary = MembersBillingSupplementary(db_pool)
        self._grouper = MembersBillingGrouper()
        self._streak_service = streak_service

    async def get_member_billing_detail(
        self,
        member_id: UUID,
    ) -> MemberBillingDetailResponse:
        """Return full billing detail for a single member and their family.

        Args:
            member_id: The member's ID.

        Returns:
            MemberBillingDetailResponse with all family memberships
            and supplementary billing data.

        Raises:
            ValueError: If no billing profile found for the member.
        """
        rows = await self._fetch_family_rows(member_id)

        if not rows:
            raise ValueError(f"No billing profile found for member_id={member_id}")

        target_row = self._find_target_profile(rows, member_id)
        parent_row = self._find_parent_profile(rows, target_row)
        gym_id = target_row["gym_id"]

        await self._supplementary.fetch_all(gym_id, member_id)
        streak_weeks = await self._streak_service.get_streak(member_id, gym_id)

        family_ids = {row["member_id"] for row in rows}
        membership_rows = [r for r in rows if r["plan_id"] is not None]

        all_grouped = self._grouper.group_by_plan(
            membership_rows,
            self._supplementary,
            member_id,
        )

        linked_to_id = target_row["account_linked_to_id"]
        if linked_to_id is not None:
            grouped = self._grouper.filter_plans_for_member(all_grouped, member_id)
        else:
            grouped = all_grouped

        has_trial, has_cancelled, has_frozen, paying_count = self._scan_membership_flags(
            membership_rows
        )
        monthly_total = parent_row["total_monthly_recurring_price"] or 0

        overview, linked_to_account = self._grouper.build_membership_overview(
            linked_to_id,
            monthly_total,
            has_trial,
            has_cancelled,
            has_frozen,
            paying_count,
            self._supplementary,
        )

        linked_accounts = self._supplementary.get_family_profiles(
            family_ids,
            member_id,
        )

        return self._build_response(
            member_id=member_id,
            gym_id=gym_id,
            target_row=target_row,
            parent_row=parent_row,
            membership_rows=membership_rows,
            grouped=grouped,
            overview=overview,
            linked_to_account=linked_to_account,
            linked_accounts=linked_accounts,
            streak_weeks=streak_weeks,
            total_monthly_recurring_price=(parent_row["total_monthly_recurring_price"]),
        )

    async def _fetch_family_rows(
        self,
        member_id: UUID,
    ) -> list:
        """Execute the family group query.

        Args:
            member_id: The member's ID.

        Returns:
            List of row mappings for the entire family.
        """
        sql = load_sql(_DETAILS_SQL / "member_details.sql")
        params = {"member_id": str(member_id)}

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            return result.mappings().all()

    def _build_response(
        self,
        member_id: UUID,
        gym_id: UUID,
        target_row: dict,
        parent_row: dict,
        membership_rows: list,
        grouped: list,
        overview: str,
        linked_to_account: UUID | None,
        linked_accounts: list,
        streak_weeks: int,
        total_monthly_recurring_price: int,
    ) -> MemberBillingDetailResponse:
        """Assemble the final MemberBillingDetailResponse."""
        return MemberBillingDetailResponse(
            member_id=member_id,
            gym_id=gym_id,
            first_name=target_row["first_name"],
            last_name=target_row["last_name"],
            photo_url=target_row["photo_url"],
            account_status=self._derive_account_status(membership_rows, member_id),
            membership_overview=overview,
            linked_to_account=linked_to_account,
            total_monthly_recurring_price=total_monthly_recurring_price,
            total_membership_count=len(membership_rows),
            personal_info=BillingPersonalInfo(
                phone=target_row["phone"],
                email=target_row["email"],
                address=target_row["address"],
                emergency_contact_name=(target_row["emergency_contact_name"]),
                emergency_contact_phone=(target_row["emergency_contact_phone"]),
                emergency_contact_email=(target_row["emergency_contact_email"]),
            ),
            linked_accounts=linked_accounts,
            memberships=grouped,
            retention=BillingRetention(
                last_class=target_row["last_class"],
                class_streak_weeks=streak_weeks,
                points_balance=(target_row["points_balance"] or 0),
                videos_watched=0,
            ),
            rank=self._build_rank(target_row),
            recently_redeemed_rewards=(self._supplementary.redeemed_rewards),
            payment_history=(self._supplementary.payment_history),
            card_on_file=self._build_card_on_file(parent_row),
        )

    def _find_target_profile(self, rows: list, member_id: UUID) -> dict:
        """Find the row belonging to the queried user.

        Args:
            rows: All query result rows.
            member_id: The queried user's ID.

        Returns:
            The first row matching the queried user.

        Raises:
            ValueError: If no matching row is found.
        """
        for row in rows:
            if row["member_id"] == member_id:
                return row
        raise ValueError(f"No profile found for member_id={member_id}")

    def _find_parent_profile(self, rows: list, target_row: dict) -> dict:
        """Find the parent account row for the queried user.

        If the target is a linked (child) account, returns the row for its
        parent; otherwise returns the target row itself.

        Args:
            rows: All query result rows (the full family group).
            target_row: The queried user's profile row.

        Returns:
            The parent account's profile row.

        Raises:
            ValueError: If the target is linked but no parent row is present.
        """
        linked_to_id = target_row["account_linked_to_id"]
        if linked_to_id is None:
            return target_row
        for row in rows:
            if row["member_id"] == linked_to_id:
                return row
        raise ValueError(f"No parent profile found for linked_to_id={linked_to_id}")

    def _scan_membership_flags(
        self,
        membership_rows: list,
    ) -> tuple[bool, bool, bool, int]:
        """Scan membership rows for status flags.

        Args:
            membership_rows: All membership rows in the family.

        Returns:
            Tuple of (has_trial, has_cancelled, has_frozen, paying_count).
            paying_count only includes active recurring memberships.
        """
        has_trial = False
        has_cancelled = False
        has_frozen = False
        paying_count = 0

        for row in membership_rows:
            row_status = row["membership_status"]
            plan_type = row["plan_type"]

            if row_status == MembershipDbStatus.frozen:
                has_frozen = True
            elif row_status == MembershipDbStatus.cancelled:
                has_cancelled = True
            elif plan_type == PlanType.trial:
                has_trial = True
            elif plan_type == PlanType.recurring and row_status == MembershipDbStatus.active:
                paying_count += 1

        return has_trial, has_cancelled, has_frozen, paying_count

    def _build_card_on_file(self, parent_row: dict) -> BillingCardOnFile | None:
        """Build the BillingCardOnFile for the paying account.

        Args:
            parent_row: The paying account's profile row.

        Returns:
            BillingCardOnFile when the parent has a saved card, else None.
        """
        brand = parent_row["card_brand"]
        last_four = parent_row["card_last_four"]
        exp_month = parent_row["card_exp_month"]
        exp_year = parent_row["card_exp_year"]
        if brand is None or last_four is None or exp_month is None or exp_year is None:
            return None
        return BillingCardOnFile(
            brand=brand,
            last_four=last_four,
            exp_month=exp_month,
            exp_year=exp_year,
        )

    def _build_rank(self, target_row: dict) -> BillingRank | None:
        """Build the BillingRank for the queried member.

        Args:
            target_row: The queried member's profile row.

        Returns:
            BillingRank when the member has a current rank, else None.
        """
        if target_row["rank_id"] is None:
            return None
        return BillingRank(
            rank_id=target_row["rank_id"],
            main_name=target_row["rank_main_name"],
            sub_name=target_row["rank_sub_name"],
            image_url=target_row["rank_image_url"],
            color=target_row["rank_color"],
            classes_till_rankup=target_row["rank_classes_till_rankup"],
        )

    def _derive_account_status(
        self,
        membership_rows: list,
        member_id: UUID,
    ) -> str | None:
        """Derive the account status from the user's memberships.

        Args:
            membership_rows: All membership rows in the family.
            member_id: The queried user's ID.

        Returns:
            The status of the user's first membership, or None.
        """
        for row in membership_rows:
            if row["member_id"] == member_id:
                return row["membership_status"]
        return None
