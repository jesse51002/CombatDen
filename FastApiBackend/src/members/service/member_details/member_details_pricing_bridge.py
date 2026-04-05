"""Bridges membership query rows to the shared pricing service."""

from uuid import UUID

from src.members.schema.member_details_schema import DiscountInfo
from src.shared.membership_pricing.membership_pricing_schema import (
    AccountPricingInput,
    AccountPricingResult,
    DiscountInput,
    MemberMembershipInput,
    PlanInput,
)
from src.shared.membership_pricing.membership_pricing_service import (
    MembershipPricingService,
)


class MemberDetailsPricingBridge:
    """Converts DB rows into pricing input and calculates prices.

    Stateless — wraps the shared MembershipPricingService with
    row-parsing logic specific to the member details query.
    """

    def __init__(self, pricing: MembershipPricingService) -> None:
        self._pricing = pricing

    def calculate_prices(
        self,
        membership_rows: list,
        discounts_dict: dict[UUID, DiscountInfo],
    ) -> AccountPricingResult:
        """Build pricing input from query rows and calculate.

        Args:
            membership_rows: Rows with membership data (plan_id
                is not None).
            discounts_dict: All active gym discounts keyed by ID.

        Returns:
            AccountPricingResult with per-membership prices.
        """
        memberships: list[MemberMembershipInput] = []
        plans: dict[UUID, PlanInput] = {}
        discounts: dict[UUID, DiscountInput] = {}

        for disc in discounts_dict.values():
            discounts[disc.discount_id] = DiscountInput(
                discount_id=disc.discount_id,
                discount_name=disc.discount_name,
                percentage_off=disc.percentage_off,
                dollar_off=disc.dollar_off,
                end_date=disc.end_date,
            )

        for row in membership_rows:
            plan_id = row["plan_id"]

            if plan_id not in plans:
                plans[plan_id] = PlanInput(
                    plan_id=plan_id,
                    plan_name=row["plan_name"],
                    plan_type=row["plan_type"],
                    base_cost=row["base_cost"],
                    additional_member_discount=(row["additional_member_discount"]),
                )

            discount_ids = _parse_discount_ids(row["discount_ids"])
            is_additional = row["account_linked_to_id"] is not None

            memberships.append(
                MemberMembershipInput(
                    crm_user_id=row["crm_user_id"],
                    plan_id=plan_id,
                    status=row["membership_status"],
                    is_additional_member=is_additional,
                    discount_ids=discount_ids,
                )
            )

        account_input = AccountPricingInput(
            memberships=memberships,
            plans=plans,
            discounts=discounts,
        )

        return self._pricing.calculate_account_prices(account_input)


def _parse_discount_ids(
    discount_ids_json: list | None,
) -> list[UUID]:
    """Parse JSONB discount_ids to a list of UUIDs.

    Args:
        discount_ids_json: Raw JSONB value.

    Returns:
        List of parsed UUIDs.
    """
    if not discount_ids_json:
        return []
    return [UUID(str(raw_id)) for raw_id in discount_ids_json]
