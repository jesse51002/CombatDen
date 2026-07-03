from datetime import datetime
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class RewardRedemptionStatus(StrEnum):
    """Mirrors the Postgres `reward_redemption_status` enum.

    Approval lifecycle for a redemption request. `pending` = awaiting admin
    decision; `approved` = admin granted the reward; `rejected` = admin denied.
    """

    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class MemberRewardRedemptionCreate(SeedModel):
    redemption_id: UUID
    gym_id: UUID
    member_id: UUID
    reward_id: UUID
    point_cost: int
    requested_at: datetime | None = None
    # Default 'approved' preserves existing seed semantics (historical
    # redemptions are treated as already granted). Set to 'pending' via
    # pending_ratio in the generator to populate the CRM approval queue.
    status: RewardRedemptionStatus = RewardRedemptionStatus.approved
    # Must be set (non-None) whenever status is not 'pending' — the DB's
    # resolved_matches_status CHECK enforces (status='pending') = (resolved_at
    # IS NULL), and the seed inserts via the supabase client so the CHECK
    # applies here too.
    resolved_at: datetime | None = None
