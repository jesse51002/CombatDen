"""Batch-fetches and resolves supplementary member detail data."""

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.member_details_schema import (
    DiscountInfo,
    LinkedAccount,
    PaymentRecord,
    RewardCard,
    TransactionItemType,
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

        async for session in self._db_pool.session():
            await self._fetch_discounts(session, gym_params)
            await self._fetch_profiles(session, gym_params)
            await self._fetch_rewards(session, gym_params)
            await self._fetch_transactions(
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
        session: object,
        params: dict[str, str],
    ) -> None:
        """Load gym discounts into lookup dict."""
        sql = load_sql(SQL_DIR / "member_details_discounts.sql")
        result = await session.execute(text(sql), params)
        for row in result.mappings().all():
            discount = DiscountInfo(
                discount_id=row["discount_id"],
                discount_name=row["discount_name"],
                discount_type=row["discount_type"],
                percentage_off=row["percentage_off"],
                dollar_off=row["dollar_off"],
                end_date=row["end_date"],
            )
            self._discounts[row["discount_id"]] = discount

    async def _fetch_profiles(
        self,
        session: object,
        params: dict[str, str],
    ) -> None:
        """Load gym profiles into lookup dict."""
        sql = load_sql(
            SQL_DIR / "member_details_linked_profiles.sql",
        )
        result = await session.execute(text(sql), params)
        for row in result.mappings().all():
            profile = LinkedAccount(
                crm_user_id=row["crm_user_id"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                photo_url=row["photo_url"],
            )
            self._profiles[row["crm_user_id"]] = profile

    async def _fetch_rewards(
        self,
        session: object,
        params: dict[str, str],
    ) -> None:
        """Load gym rewards into lookup dict."""
        sql = load_sql(SQL_DIR / "member_details_rewards.sql")
        result = await session.execute(text(sql), params)
        for row in result.mappings().all():
            reward = RewardCard(
                reward_id=row["reward_id"],
                title=row["title"],
                amount_off=row["amount_off"],
                image_url=row["image_url"],
                point_cost=row["point_cost"],
            )
            self._rewards[row["reward_id"]] = reward

    async def _fetch_transactions(
        self,
        session: object,
        params: dict[str, str],
    ) -> None:
        """Load member transactions, split into payments/rewards."""
        sql = load_sql(
            SQL_DIR / "member_details_transactions.sql",
        )
        result = await session.execute(text(sql), params)
        for row in result.mappings().all():
            item_type = row["item_type"]

            if item_type == TransactionItemType.reward_purchase:
                reward = self._rewards.get(row["item_id"])
                if reward:
                    self._redeemed_rewards.append(reward)
            else:
                payment = PaymentRecord(
                    transaction_id=row["transaction_id"],
                    item_type=item_type,
                    amount_paid=row["amount_paid"],
                    time=row["time"],
                )
                self._payment_history.append(payment)

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
