"""Groups membership rows by plan for the CRM member detail carousel."""

from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from enum import StrEnum
from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.members.schema.members_billing_schema import (
    BillingMembershipInfo,
    BillingMembershipMemberInfo,
    BillingPayingForMember,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.members_billing_supplementary import (
    MembersBillingSupplementary,
)
from src.members.service.members_status_mapping import (
    is_membership_overdue,
)
from src.memberships.memberships_schema import (
    MemberMembershipsAppliedDiscount,
)
from src.shared.formatters import format_minor_units


class OverviewKind(StrEnum):
    """Which payer-role sentence the member's overview line uses.

    A member is exactly one of these — the roles are mutually exclusive
    under the payer model (a root account pays for self/others; a linked
    child is paid for and pays for nobody).
    """

    self_pay = "self_pay"  # pays only their own membership(s)
    pays_for_others = "pays_for_others"  # pays >=1 OTHER member's membership
    beneficiary = "beneficiary"  # >=1 own membership paid by someone else


@dataclass(frozen=True)
class MembershipOverviewContext:
    """Resolved inputs for the profile-header overview string.

    The detail service computes this from the family rows (it owns the
    payer math); the grouper only formats it. ``total`` is already scoped
    to ``kind`` (what the viewed member pays for ``pays_for_others``,
    their own active-recurring sum otherwise), in minor units.
    """

    kind: OverviewKind
    total: int
    has_trial: bool
    has_cancelled: bool
    has_frozen: bool
    has_overdue: bool
    paying_count: int  # active recurring count in the scanned scope
    members_paid_for_count: int  # distinct members the viewer pays for
    own_payer_ids: frozenset[UUID]  # payers of the viewer's own memberships
    viewed_member_id: UUID


class MembersBillingGrouper:
    """Groups membership rows into cards for the membership carousel.

    Recurring plans group by plan (a family sharing a recurring plan is ONE
    card); one_time / trial packs group by membership (item_id) so a member
    can hold several of the same pack, each as its own card. Also handles
    linked-account filtering and overview string generation.
    """

    @staticmethod
    def _group_key(row: dict) -> tuple[str, UUID]:
        """Carousel grouping key.

        Recurring plans group by plan (``("plan", plan_id)``) so a family
        sharing a recurring plan stays one card; one_time / trial packs group
        by membership (``("item", item_id)``) so two packs on the same plan
        each get their own card.
        """
        if row["plan_type"] == PlanType.recurring:
            return ("plan", row["plan_id"])
        return ("item", row["item_id"])

    def group_by_plan(
        self,
        membership_rows: list,
        supplementary: MembersBillingSupplementary,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        target_member_id: UUID,
        today: date,
    ) -> list[BillingMembershipInfo]:
        """Group membership rows into carousel cards.

        Recurring plans become one card per plan; one_time / trial packs
        become one card per membership (see ``_group_key``).

        Args:
            membership_rows: Rows with membership data.
            supplementary: For discount and profile lookups.
            usage_lookup: (member_id, item_id) -> per-cycle class usage.
            target_member_id: The member whose profile is being viewed,
                used to pin them to the top of each card's paying_for list.
            today: The gym's local current date, used to derive overdue.

        Returns:
            List of BillingMembershipInfo — one per recurring plan, one per
            one_time / trial membership.
        """
        groups: dict[tuple[str, UUID], list] = defaultdict(list)
        for row in membership_rows:
            groups[self._group_key(row)].append(row)

        grouped: list[BillingMembershipInfo] = []
        for rows in groups.values():
            representative = rows[0]

            paying_for = self._build_paying_for(
                rows,
                supplementary,
                usage_lookup,
                target_member_id,
                today,
            )

            # Each row's total_price is now that membership's OWN post-discount
            # share, so the plan-level total is the SUM across the plan's rows.
            # Only active (billing) memberships count — a frozen membership is
            # paused and a cancelled/ended one keeps a stale total_price, so
            # including them would overstate what the plan currently bills.
            total_price = sum(
                row["total_price"] or 0
                for row in rows
                if row["membership_status"] == CrmMemberStatus.active
            )
            all_discounts = self._collect_plan_discounts(rows)

            members = {
                row["member_id"]: BillingMembershipMemberInfo(
                    item_id=row["item_id"],
                    paid_by_member_id=row["paid_by_member_id"],
                    end_date=row["membership_end_date"],
                    cancel_date=row["membership_cancel_date"],
                    on_outdated_price=bool(row["on_outdated_price"]),
                    base_cost=row["base_cost"],
                    total_price=row["total_price"] or 0,
                )
                for row in rows
            }

            grouped.append(
                BillingMembershipInfo(
                    plan_id=representative["plan_id"],
                    plan_name=representative["plan_name"],
                    plan_type=representative["plan_type"],
                    status=self._display_status(
                        representative["membership_status"],
                        representative["next_due_date"],
                        today,
                    ),
                    base_cost=representative["base_cost"],
                    current_active_price=representative[
                        "current_active_price"
                    ],
                    duration_amount=representative["duration_amount"],
                    duration_unit=representative["duration_unit"],
                    total_price=total_price,
                    last_paid_date=representative["last_paid_date"],
                    next_due_date=representative["next_due_date"],
                    start_date=representative["membership_start_date"],
                    freeze_start_date=representative["freeze_start_date"],
                    freeze_end_date=representative["freeze_end_date"],
                    paying_for=paying_for,
                    discounts=all_discounts,
                    members=members,
                )
            )

        return grouped

    def build_membership_overview(
        self,
        ctx: MembershipOverviewContext,
        supplementary: MembersBillingSupplementary,
    ) -> str:
        """Build the profile-header membership overview string.

        Three payer-role sentences (see :class:`OverviewKind`):

        - ``self_pay``  → ``Paying $X/mo for N Membership(s)``
        - ``pays_for_others`` → ``Paying $X/mo across N members``
        - ``beneficiary`` → ``$X/mo worth of memberships (Paid by …)``

        Salient account states (frozen / overdue / trial / cancelled)
        short-circuit the price phrase and keep their existing strings;
        the beneficiary ``(Paid by …)`` suffix is appended in every state.

        Args:
            ctx: Resolved payer-role inputs from the detail service.
            supplementary: For payer-name lookups.

        Returns:
            The overview string.
        """
        if ctx.kind == OverviewKind.pays_for_others:
            return self._overview_pays_for_others(ctx)
        if ctx.kind == OverviewKind.beneficiary:
            return self._overview_beneficiary(ctx, supplementary)
        return self._overview_self_pay(ctx)

    def _overview_self_pay(self, ctx: MembershipOverviewContext) -> str:
        """``Paying $X/mo for N Membership(s)`` — the viewer pays only
        their own memberships. Salient states keep the count suffix."""
        state = self._state_phrase(ctx)
        suffix = self._count_suffix(ctx.paying_count)
        if state is None:
            return f"Paying {format_minor_units(ctx.total)}/mo{suffix}"
        if ctx.paying_count > 0:
            return f"{state}{suffix}"
        return state

    def _overview_pays_for_others(self, ctx: MembershipOverviewContext) -> str:
        """``Paying $X/mo across N members`` — the viewer pays for >=1
        other member (self counted when they also hold a membership)."""
        members = ctx.members_paid_for_count
        state = self._state_phrase(ctx)
        across = f" across {members} members" if members > 0 else ""
        if state is None:
            return f"Paying {format_minor_units(ctx.total)}/mo{across}"
        return f"{state}{across}"

    def _overview_beneficiary(
        self,
        ctx: MembershipOverviewContext,
        supplementary: MembersBillingSupplementary,
    ) -> str:
        """``$X/mo worth of memberships (Paid by …)`` — >=1 of the
        viewer's own memberships is paid by someone else."""
        suffix = self._paid_by_suffix(ctx, supplementary)
        state = self._state_phrase(ctx)
        if state is None:
            return f"{format_minor_units(ctx.total)}/mo worth of memberships {suffix}"
        return f"{state} {suffix}"

    def _count_suffix(self, paying_count: int) -> str:
        """`` for N Membership(s)`` suffix, or empty when nothing active."""
        if paying_count <= 0:
            return ""
        label = "Membership" if paying_count == 1 else "Memberships"
        return f" for {paying_count} {label}"

    def _paid_by_suffix(
        self,
        ctx: MembershipOverviewContext,
        supplementary: MembersBillingSupplementary,
    ) -> str:
        """``(Paid by self / <name>)`` — self listed first, then payers.

        A linked child has at most one non-self payer (their linked
        parent), so the ordering is deterministic.
        """
        names: list[str] = []
        if ctx.viewed_member_id in ctx.own_payer_ids:
            names.append("self")
        for payer_id in ctx.own_payer_ids:
            if payer_id == ctx.viewed_member_id:
                continue
            profile = supplementary.profiles_dict.get(payer_id)
            names.append(profile.first_name if profile else "Primary")
        return f"(Paid by {' / '.join(names)})"

    def _state_phrase(self, ctx: MembershipOverviewContext) -> str | None:
        """Salient account-state string, or ``None`` for normal paying.

        Returns ``None`` only for the normal positive-paying state so each
        payer-role builder can supply its own price phrasing; every other
        state (frozen / overdue / active-without-total / trial / cancelled /
        none) returns its display string directly.
        """
        if ctx.has_frozen:
            return "Account is Frozen"
        if ctx.has_overdue:
            if ctx.total > 0:
                return f"Overdue · {format_minor_units(ctx.total)}/mo"
            return "Overdue"
        if ctx.total > 0:
            return None
        if ctx.paying_count > 0:
            return "Active"
        if ctx.has_trial:
            return "Member is on Trial"
        if ctx.has_cancelled:
            return "Membership is Cancelled"
        return "No active memberships"

    def _display_status(
        self,
        raw_status: str,
        next_due: date | None,
        today: date,
    ) -> CrmMemberStatus:
        """Map a raw DB membership status to its CRM display status.

        Returns ``overdue`` for a non-cancelled membership whose next
        due date has passed; otherwise the raw status unchanged.

        Args:
            raw_status: The DB-derived membership status.
            next_due: The membership's next due date, if any.
            today: The gym's local current date.

        Returns:
            The CRM-facing membership status.
        """
        if is_membership_overdue(raw_status, next_due, today):
            return CrmMemberStatus.overdue
        return CrmMemberStatus(raw_status)

    def _build_paying_for(
        self,
        rows: list,
        supplementary: MembersBillingSupplementary,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        target_member_id: UUID,
        today: date,
    ) -> list[BillingPayingForMember]:
        """Build the paying_for list for a card's rows.

        Args:
            rows: The card's membership rows (a recurring plan's family rows,
                or a single one_time / trial membership).
            supplementary: For profile lookups.
            usage_lookup: (member_id, item_id) -> per-cycle class usage.
            target_member_id: The queried member, pinned to index 0.
            today: The gym's local current date, used to derive overdue.

        Returns:
            BillingPayingForMember list, queried member first.
        """
        paying_for: list[BillingPayingForMember] = []
        for row in rows:
            uid = row["member_id"]
            profile = supplementary.profiles_dict.get(uid)

            fields: dict = {
                "member_id": uid,
                "status": self._display_status(
                    row["membership_status"],
                    row["next_due_date"],
                    today,
                ),
                "first_name": (profile.first_name if profile else row["first_name"]),
                "last_name": (profile.last_name if profile else row["last_name"]),
                "photo_url": (profile.photo_url if profile else row.get("photo_url")),
            }

            usage = usage_lookup.get((uid, row["item_id"]))
            if usage is not None:
                fields["class_count"] = usage.class_count
                fields["classes_used"] = usage.classes_used
                fields["classes_remaining"] = usage.classes_remaining

            paying_for.append(BillingPayingForMember(**fields))

        paying_for.sort(key=lambda p: p.member_id != target_member_id)
        return paying_for

    def _collect_plan_discounts(
        self,
        rows: list,
    ) -> list[MemberMembershipsAppliedDiscount]:
        """Collect every active applied-discount row across a plan's rows.

        Each row carries an ``applied_discounts`` JSONB list built by
        ``member_details.sql`` from the membership's applied-discount rows
        (already filtered to currently-active ones), each resolved to its
        pinned value version. Applied-discount rows are item-scoped, so they
        are NOT de-duplicated — the CRM groups them under each covered member
        by ``item_id`` and removes one by ``applied_discount_id``.

        Args:
            rows: Membership rows sharing the same plan.

        Returns:
            One MemberMembershipsAppliedDiscount per active applied-discount row.
        """
        discounts: list[MemberMembershipsAppliedDiscount] = []
        for row in rows:
            for applied in row["applied_discounts"] or []:
                discounts.append(MemberMembershipsAppliedDiscount(**applied))
        return discounts

