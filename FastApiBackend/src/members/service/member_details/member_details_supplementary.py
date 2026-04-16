"""Batch-fetches and resolves supplementary member detail data."""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.member_details_schema import (
    DiscountInfo,
    LineItemRecord,
    LinkedAccount,
    PaymentRecord,
    RewardCard,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class MemberDetailsSupplementary:
    """Fetches supplementary data and provides per-member lookups.

    Executes batch queries for discounts, linked profiles,
    transactions, and rewards, then exposes resolver methods.

    Args:
        db_pool: Database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool
        self._discounts: dict[UUID, DiscountInfo] = {}
        self._profiles: dict[UUID, LinkedAccount] = {}
        self._rewards: dict[UUID, RewardCard] = {}
        self._payment_history: list[PaymentRecord] = []
        self._redeemed_rewards: list[RewardCard] = []

    async def fetch_all(
        self,
        gym_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Execute all supplementary queries and build lookups.

        Args:
            gym_id: The gym to fetch data for.
            crm_user_id: The member to fetch data for.
        """
        self._reset()
        gym_params = {"gym_id": str(gym_id)}
        member_params = {
            "gym_id": str(gym_id),
            "crm_user_id": str(crm_user_id),
        }

        async with self._db_pool.session() as session:
            self._discounts = await self._fetch_discounts(
                session,
                gym_params,
            )
            self._profiles = await self._fetch_profiles(
                session,
                gym_params,
            )
            self._rewards = await self._fetch_rewards(
                session,
                gym_params,
            )
            self._payment_history = await self._fetch_charges(
                session,
                member_params,
            )
            self._redeemed_rewards = await self._fetch_reward_redemptions(
                session,
                member_params,
            )

    def _reset(self) -> None:
        """Clear all internal lookup state."""
        self._discounts.clear()
        self._profiles.clear()
        self._rewards.clear()
        self._payment_history.clear()
        self._redeemed_rewards.clear()

    async def _fetch_discounts(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> dict[UUID, DiscountInfo]:
        """Load gym discounts into lookup dict."""
        sql = load_sql(SQL_DIR / "member_details" / "member_details_discounts.sql")
        result = await session.execute(text(sql), params)
        discounts: dict[UUID, DiscountInfo] = {}
        for row in result.mappings().all():
            discount = DiscountInfo(
                discount_id=row["discount_id"],
                discount_name=row["discount_name"],
                discount_type=row["discount_type"],
                percentage_off=row["percentage_off"],
                dollar_off=row["dollar_off"],
            )
            discounts[row["discount_id"]] = discount
        return discounts

    async def _fetch_profiles(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> dict[UUID, LinkedAccount]:
        """Load gym profiles into lookup dict."""
        sql = load_sql(
            SQL_DIR / "member_details" / "member_details_linked_profiles.sql",
        )
        result = await session.execute(text(sql), params)
        profiles: dict[UUID, LinkedAccount] = {}
        for row in result.mappings().all():
            profile = LinkedAccount(
                crm_user_id=row["crm_user_id"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                photo_url=row["photo_url"],
            )
            profiles[row["crm_user_id"]] = profile
        return profiles

    async def _fetch_rewards(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> dict[UUID, RewardCard]:
        """Load gym rewards into lookup dict."""
        sql = load_sql(SQL_DIR / "member_details" / "member_details_rewards.sql")
        result = await session.execute(text(sql), params)
        rewards: dict[UUID, RewardCard] = {}
        for row in result.mappings().all():
            reward = RewardCard(
                reward_id=row["reward_id"],
                title=row["title"],
                amount_off=row["amount_off"],
                image_url=row["image_url"],
                point_cost=row["point_cost"],
            )
            rewards[row["reward_id"]] = reward
        return rewards

    async def _fetch_charges(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> list[PaymentRecord]:
        """Load member charges with aggregated line items and applied discounts."""
        sql = load_sql(
            SQL_DIR / "member_details" / "member_details_transactions.sql",
        )
        result = await session.execute(text(sql), params)
        payments: list[PaymentRecord] = []
        for row in result.mappings().all():
            line_items = [
                LineItemRecord(
                    line_item_id=li["line_item_id"],
                    item_type=li["item_type"],
                    name=li["name"],
                    amount=li["amount"],
                    stripe_product_id=li.get("stripe_product_id"),
                    item_id=(UUID(li["item_id"]) if li.get("item_id") else None),
                )
                for li in (row["line_items"] or [])
            ]

            applied: list[DiscountInfo] = []
            for ad in row["applied_discounts"] or []:
                discount = self._discounts.get(UUID(ad["discount_id"]))
                if discount:
                    applied.append(discount)

            payments.append(
                PaymentRecord(
                    charge_id=row["charge_id"],
                    invoice_id=row["invoice_id"],
                    kind=row["kind"],
                    status=row["status"],
                    amount=row["amount"],
                    currency=row["currency"],
                    payment_method_type=row["payment_method_type"],
                    charge_time=row["charge_time"],
                    refunds_charge_id=row["refunds_charge_id"],
                    line_items=line_items,
                    applied_discounts=applied,
                )
            )
        return payments

    async def _fetch_reward_redemptions(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> list[RewardCard]:
        """Load member reward redemptions joined with gym_rewards."""
        sql = load_sql(
            SQL_DIR / "member_details" / "member_details_reward_redemptions.sql",
        )
        result = await session.execute(text(sql), params)
        redeemed: list[RewardCard] = []
        for row in result.mappings().all():
            redeemed.append(
                RewardCard(
                    reward_id=row["reward_id"],
                    title=row["title"],
                    amount_off=row["amount_off"],
                    image_url=row["image_url"],
                    point_cost=row["point_cost"],
                )
            )
        return redeemed

    def get_discounts(
        self,
        discount_ids_json: list | None,
    ) -> list[DiscountInfo]:
        """Resolve discount IDs from JSONB to DiscountInfo list.

        Args:
            discount_ids_json: Raw JSONB value (list of UUID
                strings or None).

        Returns:
            List of matching DiscountInfo objects.
        """
        if not discount_ids_json:
            return []
        discounts = []
        for raw_id in discount_ids_json:
            uid = UUID(str(raw_id))
            discount = self._discounts.get(uid)
            if discount:
                discounts.append(discount)
        return discounts

    def get_family_profiles(
        self,
        family_ids: set[UUID],
        exclude_id: UUID,
    ) -> list[LinkedAccount]:
        """Get LinkedAccount objects for family members.

        Args:
            family_ids: All crm_user_ids in the family group.
            exclude_id: The queried user's ID to exclude.

        Returns:
            LinkedAccount list for all family members except
            the excluded user.
        """
        accounts = []
        for uid in family_ids:
            if uid == exclude_id:
                continue
            profile = self._profiles.get(uid)
            if profile:
                accounts.append(profile)
        return accounts

    @property
    def discounts_dict(self) -> dict[UUID, DiscountInfo]:
        """Return the raw discounts lookup dict."""
        return self._discounts

    @property
    def profiles_dict(self) -> dict[UUID, LinkedAccount]:
        """Return the raw profiles lookup dict."""
        return self._profiles

    @property
    def payment_history(self) -> list[PaymentRecord]:
        """Return all payment records for the member."""
        return self._payment_history

    @property
    def redeemed_rewards(self) -> list[RewardCard]:
        """Return all recently redeemed rewards for the member."""
        return self._redeemed_rewards
