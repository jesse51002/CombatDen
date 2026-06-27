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
    """Request-scoped loader for one member-detail page's supplementary data.

    NOT a shared service: construct a fresh one per request with the
    ``(gym_id, member_id)`` it is scoped to, ``await load()`` once, then read
    the results via the accessors. Holding the scope on the instance (rather
    than passing it to a method on a long-lived object) is what makes the
    per-request statefulness correct by construction.

    Args:
        db_pool: Database connection pool.
        gym_id: The gym this loader is scoped to.
        member_id: The member this loader is scoped to.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_id: UUID,
        member_id: UUID,
    ) -> None:
        self._db_pool = db_pool
        self._gym_id = gym_id
        self._member_id = member_id
        self._rewards: dict[UUID, BillingRewardCard] = {}
        self._redeemed_rewards: list[BillingRewardCard] = []
        self._authorized_payers: list[BillingLinkedAccount] = []
        self._authorized_to_pay_for: list[BillingLinkedAccount] = []

    async def load(self) -> None:
        """Execute all supplementary queries for this loader's gym + member."""
        gym_params = {"gym_id": str(self._gym_id)}
        member_params = {
            "gym_id": str(self._gym_id),
            "member_id": str(self._member_id),
        }

        async with self._db_pool.session() as session:
            self._rewards = await self._fetch_rewards(session, gym_params)
            self._redeemed_rewards = await self._fetch_reward_redemptions(
                session,
                member_params,
            )
            self._authorized_payers = await self._fetch_roster(
                session,
                member_params,
                "member_details_authorized_payers.sql",
            )
            self._authorized_to_pay_for = await self._fetch_roster(
                session,
                member_params,
                "member_details_authorized_to_pay_for.sql",
            )

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

    async def _fetch_roster(
        self,
        session: AsyncSession,
        params: dict[str, str],
        sql_file: str,
    ) -> list[BillingLinkedAccount]:
        """Load an authorization roster (junction → profiles) in order."""
        sql = load_sql(_DETAILS_SQL / sql_file)
        result = await session.execute(text(sql), params)
        return [
            BillingLinkedAccount(
                member_id=row["member_id"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                photo_url=row["photo_url"],
            )
            for row in result.mappings().all()
        ]

    @property
    def redeemed_rewards(self) -> list[BillingRewardCard]:
        """Return all recently redeemed rewards for the member."""
        return self._redeemed_rewards

    @property
    def authorized_payers(self) -> list[BillingLinkedAccount]:
        """Members authorized to pay for the viewed member."""
        return self._authorized_payers

    @property
    def authorized_to_pay_for(self) -> list[BillingLinkedAccount]:
        """Members the viewed member is authorized to pay for."""
        return self._authorized_to_pay_for
