"""Background service for recalculating family membership prices."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.shared import SQL_DIR as SHARED_SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.membership_pricing.membership_pricing_schema import (
    AccountPricingInput,
    DiscountInput,
    MemberMembershipInput,
    PlanInput,
)
from src.shared.membership_pricing.membership_pricing_service import MembershipPricingService
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberDetailsPriceRecalc:
    """Recalculates and updates membership prices for a family group.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        pricing: MembershipPricingService,
    ) -> None:
        self._db_pool = db_pool
        self._pricing = pricing

    async def recalculate_family_prices(
        self,
        gym_id: UUID,
        family_ids: set[UUID],
    ) -> None:
        """Recalculate and update total_price for family memberships.

        Fetches all active memberships for the family group,
        recalculates prices using current discount values, and
        updates any rows where the price has changed.

        Args:
            gym_id: The gym ID.
            family_ids: All crm_user_ids in the family group.
        """
        recalc_sql = load_sql(SQL_DIR / "member_details" / "member_details_recalc.sql")
        update_sql = load_sql(
            SHARED_SQL_DIR / "update_membership_price.sql",
        )
        discount_sql = load_sql(
            SQL_DIR / "member_details" / "member_details_discounts.sql",
        )

        async with self._db_pool.session() as session:
            discounts = await self._fetch_discounts(
                session,
                discount_sql,
                gym_id,
            )

            family_ids_list = [str(uid) for uid in family_ids]
            result = await session.execute(
                text(recalc_sql),
                {
                    "gym_id": str(gym_id),
                    "family_ids": family_ids_list,
                },
            )
            rows = result.mappings().all()

            if not rows:
                return

            pricing_result = self._build_and_calculate(
                rows,
                discounts,
            )

            price_lookup = {
                (p.crm_user_id, p.plan_id): p.calculated_price
                for p in pricing_result.membership_prices
            }

            for row in rows:
                key = (row["crm_user_id"], row["plan_id"])
                new_price = price_lookup.get(key)
                if new_price is None:
                    continue

                old_price = row["total_price"]
                if abs(new_price - old_price) < 0.01:
                    continue

                await session.execute(
                    text(update_sql),
                    {
                        "total_price": new_price,
                        "crm_user_id": str(row["crm_user_id"]),
                        "gym_id": str(gym_id),
                        "plan_id": str(row["plan_id"]),
                    },
                )

            await session.commit()

    async def _fetch_discounts(
        self,
        session: object,
        sql: str,
        gym_id: UUID,
    ) -> dict[UUID, DiscountInput]:
        """Fetch active gym discounts.

        Args:
            session: Active database session.
            sql: The discount query SQL.
            gym_id: The gym to fetch discounts for.

        Returns:
            Dict of DiscountInput keyed by discount_id.
        """
        result = await session.execute(
            text(sql),
            {"gym_id": str(gym_id)},
        )
        discounts: dict[UUID, DiscountInput] = {}
        for row in result.mappings().all():
            discounts[row["discount_id"]] = DiscountInput(
                discount_id=row["discount_id"],
                discount_name=row["discount_name"],
                percentage_off=row["percentage_off"],
                dollar_off=row["dollar_off"],
                end_date=row["end_date"],
            )
        return discounts

    def _build_and_calculate(
        self,
        rows: list,
        discounts: dict[UUID, DiscountInput],
    ) -> object:
        """Build pricing input from rows and calculate.

        Args:
            rows: Membership rows from the recalc query.
            discounts: Active gym discounts.

        Returns:
            AccountPricingResult with recalculated prices.
        """
        memberships: list[MemberMembershipInput] = []
        plans: dict[UUID, PlanInput] = {}

        for row in rows:
            plan_id = row["plan_id"]

            if plan_id not in plans:
                plans[plan_id] = PlanInput(
                    plan_id=plan_id,
                    plan_name=row["plan_name"],
                    plan_type=row["plan_type"],
                    base_cost=row["base_cost"],
                    additional_member_discount=(row["additional_member_discount"]),
                )

            discount_ids = []
            if row["discount_ids"]:
                discount_ids = [UUID(str(d)) for d in row["discount_ids"]]

            memberships.append(
                MemberMembershipInput(
                    crm_user_id=row["crm_user_id"],
                    plan_id=plan_id,
                    status=row["status"],
                    is_additional_member=(row["account_linked_to_id"] is not None),
                    discount_ids=discount_ids,
                )
            )

        account_input = AccountPricingInput(
            memberships=memberships,
            plans=plans,
            discounts=discounts,
        )

        return self._pricing.calculate_account_prices(account_input)
