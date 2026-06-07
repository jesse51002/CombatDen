"""Batch-fetches and resolves supplementary member billing detail data."""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    BillingLinkedAccount,
    BillingRewardCard,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_DETAILS_SQL = SQL_DIR / "member_details"


class MembersBillingSupplementary:
    """Fetches supplementary data and provides per-member lookups.

    Executes batch queries for discounts, linked profiles, transactions,
    and rewards, then exposes resolver methods.

    Args:
        db_pool: Database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool
        self._profiles: dict[UUID, BillingLinkedAccount] = {}
        self._rewards: dict[UUID, BillingRewardCard] = {}
        self._redeemed_rewards: list[BillingRewardCard] = []

    async def fetch_all(
        self,
        gym_id: UUID,
        member_id: UUID,
    ) -> None:
        """Execute all supplementary queries and build lookups.

        Args:
            gym_id: The gym to fetch data for.
            member_id: The member to fetch data for.
        """
        self._reset()
        gym_params = {"gym_id": str(gym_id)}
        member_params = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
        }

        async with self._db_pool.session() as session:
            self._profiles = await self._fetch_profiles(session, gym_params)
            self._rewards = await self._fetch_rewards(session, gym_params)
            self._redeemed_rewards = await self._fetch_reward_redemptions(
                session,
                member_params,
            )

    def _reset(self) -> None:
        """Clear all internal lookup state."""
        self._profiles.clear()
        self._rewards.clear()
        self._redeemed_rewards.clear()

    async def _fetch_profiles(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> dict[UUID, BillingLinkedAccount]:
        """Load gym billing profiles into lookup dict."""
        sql = load_sql(_DETAILS_SQL / "member_details_linked_profiles.sql")
        result = await session.execute(text(sql), params)
        profiles: dict[UUID, BillingLinkedAccount] = {}
        for row in result.mappings().all():
            profile = BillingLinkedAccount(
                member_id=row["member_id"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                photo_url=row["photo_url"],
            )
            profiles[row["member_id"]] = profile
        return profiles

    async def _fetch_rewards(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> dict[UUID, BillingRewardCard]:
        """Load gym rewards into lookup dict."""
        sql = load_sql(_DETAILS_SQL / "member_details_rewards.sql")
        result = await session.execute(text(sql), params)
        rewards: dict[UUID, BillingRewardCard] = {}
        for row in result.mappings().all():
            reward = BillingRewardCard(
                reward_id=row["reward_id"],
                title=row["title"],
                amount_off=row["amount_off"],
                image_url=row["image_url"],
                point_cost=row["point_cost"],
            )
            rewards[row["reward_id"]] = reward
        return rewards

    async def _fetch_reward_redemptions(
        self,
        session: AsyncSession,
        params: dict[str, str],
    ) -> list[BillingRewardCard]:
        """Load member reward redemptions joined with gym_rewards."""
        sql = load_sql(_DETAILS_SQL / "member_details_reward_redemptions.sql")
        result = await session.execute(text(sql), params)
        redeemed: list[BillingRewardCard] = []
        for row in result.mappings().all():
            redeemed.append(
                BillingRewardCard(
                    reward_id=row["reward_id"],
                    title=row["title"],
                    amount_off=row["amount_off"],
                    image_url=row["image_url"],
                    point_cost=row["point_cost"],
                )
            )
        return redeemed

    def get_family_profiles(
        self,
        family_ids: set[UUID],
        exclude_id: UUID,
    ) -> list[BillingLinkedAccount]:
        """Get BillingLinkedAccount objects for family members.

        Args:
            family_ids: All member_ids in the family group.
            exclude_id: The queried user's ID to exclude.

        Returns:
            BillingLinkedAccount list for all family members except
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
    def profiles_dict(self) -> dict[UUID, BillingLinkedAccount]:
        """Return the raw profiles lookup dict."""
        return self._profiles

    @property
    def redeemed_rewards(self) -> list[BillingRewardCard]:
        """Return all recently redeemed rewards for the member."""
        return self._redeemed_rewards
