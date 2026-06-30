"""Service for fetching full member billing detail data."""

from collections import defaultdict
from datetime import date
from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.checkin.service.cycle_counts_service import CycleCountsService
from src.checkin.service.streak_service import StreakService
from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    BillingCardOnFile,
    BillingPaysForMember,
    BillingPaysForMembership,
    BillingPersonalInfo,
    BillingRank,
    BillingRetention,
    MemberBillingDetailResponse,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.member_details_cycle_counts_bridge import (
    MemberDetailsCycleCountsBridge,
)
from src.members.service.member_details.members_billing_grouper import (
    MembersBillingGrouper,
    MembershipOverviewContext,
)
from src.members.service.member_details.members_billing_supplementary import (
    MembersBillingSupplementary,
)
from src.members.service.members_status_mapping import (
    is_membership_overdue,
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
        cycle_counts_service: Injected per-cycle class-usage service.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        streak_service: StreakService,
        cycle_counts_service: CycleCountsService,
    ) -> None:
        self._db_pool = db_pool
        self._grouper = MembersBillingGrouper()
        self._streak_service = streak_service
        self._cycle_counts_bridge = MemberDetailsCycleCountsBridge(
            cycle_counts_service,
        )

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
        gym_id = target_row["gym_id"]
        today = target_row["gym_today"]

        supplementary = MembersBillingSupplementary(
            self._db_pool,
            gym_id,
            member_id,
        )
        await supplementary.load()
        streak_weeks = await self._streak_service.get_streak(member_id, gym_id)

        # The query returns the viewed member + every member they PAY FOR
        # (paid_by_member_id) so `pays_for` (the freeze-impact roster) can see
        # the funded memberships. The carousel and overview are scoped to the
        # viewed member's OWN rows only.
        all_membership_rows = [r for r in rows if r["plan_id"] is not None]
        own_membership_rows = [
            r for r in all_membership_rows if r["member_id"] == member_id
        ]

        usage_lookup = await self._cycle_counts_bridge.fetch_usage(
            gym_id,
            [member_id],
        )

        grouped = self._grouper.build_membership_cards(
            own_membership_rows,
            usage_lookup,
            today,
        )

        overview_ctx = self._build_overview_context(
            own_membership_rows,
            today,
        )
        overview = self._grouper.build_membership_overview(overview_ctx)

        pays_for = self._build_pays_for(member_id, all_membership_rows)

        return self._build_response(
            member_id=member_id,
            gym_id=gym_id,
            target_row=target_row,
            membership_rows=own_membership_rows,
            grouped=grouped,
            overview=overview,
            authorized_payers=supplementary.authorized_payers,
            authorized_to_pay_for=supplementary.authorized_to_pay_for,
            pays_for=pays_for,
            redeemed_rewards=supplementary.redeemed_rewards,
            streak_weeks=streak_weeks,
            # Per-payer semantics: the QUERIED member's own row carries what
            # THEY pay monthly (the sync writes each payer's own total; a
            # member who pays nothing reads 0).
            total_monthly_recurring_price=(
                target_row["total_monthly_recurring_price"] or 0
            ),
            today=today,
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
        membership_rows: list,
        grouped: list,
        overview: str,
        authorized_payers: list,
        authorized_to_pay_for: list,
        pays_for: list,
        redeemed_rewards: list,
        streak_weeks: int,
        total_monthly_recurring_price: int,
        today: date,
    ) -> MemberBillingDetailResponse:
        """Assemble the final MemberBillingDetailResponse."""
        return MemberBillingDetailResponse(
            member_id=member_id,
            gym_id=gym_id,
            first_name=target_row["first_name"],
            last_name=target_row["last_name"],
            photo_url=target_row["photo_url"],
            account_status=self._derive_account_status(
                membership_rows,
                member_id,
                today,
            ),
            membership_overview=overview,
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
            authorized_payers=authorized_payers,
            authorized_to_pay_for=authorized_to_pay_for,
            pays_for=pays_for,
            memberships=grouped,
            retention=BillingRetention(
                last_class=target_row["last_class"],
                class_streak_weeks=streak_weeks,
                points_balance=(target_row["points_balance"] or 0),
                videos_watched=0,
            ),
            rank=self._build_rank(target_row),
            recently_redeemed_rewards=redeemed_rewards,
            card_on_file=self._build_card_on_file(target_row),
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

    def _scan_membership_flags(
        self,
        membership_rows: list,
        today: date,
    ) -> tuple[bool, bool, bool, bool, int, int, int]:
        """Scan membership rows for status flags.

        Args:
            membership_rows: All membership rows in the family.
            today: The gym's local current date, used to derive overdue.

        Returns:
            Tuple of (has_trial, has_cancelled, has_frozen, has_overdue,
            paying_count, one_time_count, one_time_total). ``paying_count``
            only includes active recurring memberships; ``one_time_count`` /
            ``one_time_total`` are the active one-time (class-pack) count + the
            sum of what was paid for them (minor units).
        """
        has_trial = False
        has_cancelled = False
        has_frozen = False
        has_overdue = False
        paying_count = 0
        one_time_count = 0
        one_time_total = 0

        for row in membership_rows:
            row_status = row["membership_status"]
            plan_type = row["plan_type"]

            if is_membership_overdue(row_status, row["next_due_date"], today):
                has_overdue = True

            if row_status == MembershipDbStatus.frozen:
                has_frozen = True
            elif row_status == MembershipDbStatus.cancelled:
                has_cancelled = True
            elif plan_type == PlanType.trial:
                has_trial = True
            elif plan_type == PlanType.recurring and row_status == MembershipDbStatus.active:
                paying_count += 1
            elif plan_type == PlanType.one_time and row_status == MembershipDbStatus.active:
                one_time_count += 1
                one_time_total += row["total_price"] or 0

        return (
            has_trial,
            has_cancelled,
            has_frozen,
            has_overdue,
            paying_count,
            one_time_count,
            one_time_total,
        )

    def _member_paying_total(self, rows: list) -> int:
        """Sum total_price across the active recurring memberships in ``rows``.

        Each membership's ``total_price`` is that member's own post-discount
        share, so summing one member's active recurring rows yields their own
        monthly recurring bill — used for a linked account's overview.
        """
        return sum(
            row["total_price"] or 0
            for row in rows
            if row["plan_type"] == PlanType.recurring
            and row["membership_status"] == MembershipDbStatus.active
        )

    def _build_overview_context(
        self,
        own_rows: list,
        today: date,
    ) -> MembershipOverviewContext:
        """Resolve the overview inputs for the viewed member's own rows.

        Scoped to the member's own memberships — ``total`` is their own
        active-recurring monthly sum and the flags / count are scanned over
        the same rows.

        Args:
            own_rows: The viewed member's OWN membership rows.
            today: The gym's local date, for the overdue derivation.

        Returns:
            The resolved overview context.
        """
        total = self._member_paying_total(own_rows)
        (
            has_trial,
            has_cancelled,
            has_frozen,
            has_overdue,
            paying_count,
            one_time_count,
            one_time_total,
        ) = self._scan_membership_flags(own_rows, today)

        return MembershipOverviewContext(
            total=total,
            has_trial=has_trial,
            has_cancelled=has_cancelled,
            has_frozen=has_frozen,
            has_overdue=has_overdue,
            paying_count=paying_count,
            one_time_count=one_time_count,
            one_time_total=one_time_total,
        )

    def _build_pays_for(
        self,
        member_id: UUID,
        all_rows: list,
    ) -> list[BillingPaysForMember]:
        """The recurring memberships the viewed member funds, grouped by
        the member who holds them — every row where
        ``paid_by_member_id == member_id`` (the viewed member's own
        self-paid ones included). This is exactly what a freeze on the
        viewed member would pause. The viewed member sorts first.

        Args:
            member_id: The viewed member (the payer).
            all_rows: Every family membership row.

        Returns:
            One entry per member the viewer pays for, with the funded
            memberships; empty when they fund nothing recurring.
        """
        by_member: dict[UUID, list[dict]] = defaultdict(list)
        for row in all_rows:
            if row["paid_by_member_id"] != member_id:
                continue
            if not self._is_current_recurring(row):
                continue
            by_member[row["member_id"]].append(row)

        ordered = sorted(
            by_member.keys(),
            key=lambda mid: mid != member_id,
        )
        return [
            BillingPaysForMember(
                member_id=mid,
                first_name=by_member[mid][0]["first_name"],
                last_name=by_member[mid][0]["last_name"],
                photo_url=by_member[mid][0].get("photo_url"),
                memberships=[
                    BillingPaysForMembership(
                        item_id=row["item_id"],
                        plan_name=row["plan_name"],
                    )
                    for row in by_member[mid]
                ],
            )
            for mid in ordered
        ]

    def _is_current_recurring(self, row: dict) -> bool:
        """Whether ``row`` is a current recurring membership that will still bill.

        Frozen is paused-but-current, so it still counts toward who-pays-whom
        even though it bills nothing this cycle. A membership with a
        ``cancel_date`` set is already on its way out (its Stripe line is
        removed and it will never bill again) — even though the status view
        still reads ``active`` until cancel_date elapses — so it is NOT current
        and must not show as funded ("Cancels: X").
        """
        return (
            row["plan_type"] == PlanType.recurring
            and row["membership_cancel_date"] is None
            and row["membership_status"]
            in (MembershipDbStatus.active, MembershipDbStatus.frozen)
        )

    def _build_card_on_file(self, member_row: dict) -> BillingCardOnFile | None:
        """Build the BillingCardOnFile for the member's OWN saved card.

        Per-payer billing: each member's ``card_on_file`` is THEIR OWN
        saved card (their own Stripe customer's default), never a linked
        parent's — so a payer-scoped read (the charge dialog / start
        wizard fetching the chosen payer's billing) shows the card that
        will actually be charged. A member with no own card reads None.

        Args:
            member_row: The queried member's OWN profile row.

        Returns:
            BillingCardOnFile when the member has a saved card, else None.
        """
        brand = member_row["card_brand"]
        last_four = member_row["card_last_four"]
        exp_month = member_row["card_exp_month"]
        exp_year = member_row["card_exp_year"]
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
        today: date,
    ) -> str | None:
        """Derive the account status from the user's memberships.

        Returns ``overdue`` when the user's first membership is past due
        (matching the members-list derivation); otherwise the raw DB
        status.

        Args:
            membership_rows: All membership rows in the family.
            member_id: The queried user's ID.
            today: The gym's local current date, used to derive overdue.

        Returns:
            The status of the user's first membership, or None.
        """
        for row in membership_rows:
            if row["member_id"] == member_id:
                if is_membership_overdue(
                    row["membership_status"],
                    row["next_due_date"],
                    today,
                ):
                    return CrmMemberStatus.overdue
                return row["membership_status"]
        return None
