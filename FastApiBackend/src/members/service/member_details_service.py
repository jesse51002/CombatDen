"""Service for fetching member detail data."""

from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.members import SQL_DIR
from src.members.schema.member_details_schema import (
    CardOnFile,
    MemberDetailResponse,
    PersonalInfo,
    Retention,
)
from src.members.service.member_details.member_details_cycle_counts_bridge import (
    MemberDetailsCycleCountsBridge,
)
from src.members.service.member_details.member_details_membership_grouper import (
    MemberDetailsMembershipGrouper,
)
from src.members.service.member_details.member_details_streak_bridge import (
    MemberDetailsStreakBridge,
)
from src.members.service.member_details.member_details_supplementary import (
    MemberDetailsSupplementary,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class MemberService:
    """Service for member detail operations.

    Orchestrates sub-services to fetch, group, and
    assemble the full member detail response.

    Args:
        db_pool: Injected database connection pool.
        cycle_counts_service: Injected cycle counts service.
        streak_service: Injected streak service.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        cycle_counts_service: ClassesCycleCountsService,
        streak_service: ClassesStreakService,
    ) -> None:
        self._db_pool = db_pool
        self._supplementary = MemberDetailsSupplementary(db_pool)
        self._cycle_counts_bridge = MemberDetailsCycleCountsBridge(
            cycle_counts_service,
        )
        self._streak_bridge = MemberDetailsStreakBridge(streak_service)
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
        parent_row = _find_parent_profile(rows, target_row)
        gym_id = target_row["gym_id"]

        await self._supplementary.fetch_all(gym_id, crm_user_id)
        streak_weeks = await self._streak_bridge.fetch_streak(
            gym_id,
            crm_user_id,
        )

        family_ids = {row["crm_user_id"] for row in rows}
        membership_rows = [r for r in rows if r["plan_id"] is not None]

        usage_lookup = await self._cycle_counts_bridge.fetch_usage(
            gym_id,
            list(family_ids),
        )

        all_grouped = self._grouper.group_by_plan(
            membership_rows,
            self._supplementary,
            usage_lookup,
            crm_user_id,
        )

        linked_to_id = target_row["account_linked_to_id"]
        if linked_to_id is not None:
            grouped = self._grouper.filter_plans_for_member(
                all_grouped,
                crm_user_id,
            )
        else:
            grouped = all_grouped

        has_trial, has_cancelled, has_frozen, paying_count = _scan_membership_flags(
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
            crm_user_id,
        )

        return self._build_response(
            crm_user_id=crm_user_id,
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
        crm_user_id: UUID,
    ) -> list:
        """Execute the family group query.

        Args:
            crm_user_id: The member's CRM user ID.

        Returns:
            List of row mappings for the entire family.
        """
        sql = load_sql(SQL_DIR / "member_details" / "member_details.sql")
        params = {"crm_user_id": str(crm_user_id)}

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            return result.mappings().all()

    def _build_response(
        self,
        crm_user_id: UUID,
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
    ) -> MemberDetailResponse:
        """Assemble the final MemberDetailResponse.

        Args:
            crm_user_id: The queried user's ID.
            gym_id: The gym ID.
            target_row: The queried user's profile row.
            parent_row: The paying account's profile row
                (the target itself if the target is not
                linked). Source of card-on-file fields.
            membership_rows: All family membership rows.
            grouped: Grouped MembershipInfo list.
            overview: Membership overview string.
            linked_to_account: Primary account ID or None.
            linked_accounts: LinkedAccount list.
            streak_weeks: Class streak in weeks.
            total_monthly_recurring_price: Parent account's monthly
                recurring total.

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
            total_monthly_recurring_price=total_monthly_recurring_price,
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
                class_streak_weeks=streak_weeks,
                points_balance=(target_row["points_balance"] or 0),
                videos_watched=0,
            ),
            recently_redeemed_rewards=(self._supplementary.redeemed_rewards),
            payment_history=(self._supplementary.payment_history),
            card_on_file=_build_card_on_file(parent_row),
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


def _find_parent_profile(rows: list, target_row: dict) -> dict:
    """Find the parent account row for the queried user.

    If the target is a linked (child) account, returns the row for
    its parent; otherwise returns the target row itself.

    Args:
        rows: All query result rows (the full family group).
        target_row: The queried user's profile row.

    Returns:
        The parent account's profile row.

    Raises:
        ValueError: If the target is linked but no parent row is
            present in the family rows.
    """
    linked_to_id = target_row["account_linked_to_id"]
    if linked_to_id is None:
        return target_row
    for row in rows:
        if row["crm_user_id"] == linked_to_id:
            return row
    raise ValueError(f"No parent profile found for linked_to_id={linked_to_id}")


def _scan_membership_flags(
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


def _build_card_on_file(parent_row: dict) -> CardOnFile | None:
    """Build the CardOnFile for the paying account.

    Args:
        parent_row: The paying account's profile row.

    Returns:
        CardOnFile when the parent has a saved card, otherwise
        None. All four fields must be populated — the schema
        stores them together and the Stripe sync path always
        writes them as a set.
    """
    brand = parent_row["card_brand"]
    last_four = parent_row["card_last_four"]
    exp_month = parent_row["card_exp_month"]
    exp_year = parent_row["card_exp_year"]
    if brand is None or last_four is None or exp_month is None or exp_year is None:
        return None
    return CardOnFile(
        brand=brand,
        last_four=last_four,
        exp_month=exp_month,
        exp_year=exp_year,
    )


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
