"""Pydantic models for the rewards domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator
from schema.member_reward_redemption import RewardRedemptionStatus

import src.shared.db_schema_path  # noqa: F401  — ensures ``from schema.*`` path is set up


class RewardCreateRequest(BaseModel):
    """Body for POST /api/v1/rewards/.

    ``image_url`` stays optional — every reward HAS an image
    (``gym_rewards.image_url`` is NOT NULL), but the service fills the
    platform default (``settings.default_reward_image_url``) when none is
    provided, mirroring ``GymClassCreateRequest``. ``price_label`` is
    required — the founder decision that every reward carries a value badge.
    """

    gym_id: UUID
    title: str = Field(min_length=1)
    point_cost: int = Field(gt=0)
    image_url: str | None = None
    price_label: str = Field(min_length=1)


class RewardUpdateData(BaseModel):
    """Mutable fields on a reward row.

    Every non-``is_active`` field here maps to a NOT NULL column on
    ``gym_rewards`` (``title``, ``point_cost``, ``image_url``,
    ``price_label``), so each can be changed but never cleared. Patch
    semantics: an absent field leaves the column unchanged; an explicit
    ``null`` 422s instead of silently resetting to a default (unlike the
    classes identity-update path) — or reaching the SET clause as a
    NOT NULL violation that would surface as a 500.
    """

    title: str | None = None
    point_cost: int | None = Field(default=None, gt=0)
    image_url: str | None = None
    price_label: str | None = None
    is_active: bool | None = None

    @field_validator("title", "point_cost", "image_url", "price_label")
    @classmethod
    def _reject_explicit_null(
        cls, value: str | int | None, info
    ) -> str | int | None:
        """Only runs when the field is explicitly present in the request
        body (Pydantic skips validators on an unset default), so an absent
        field is untouched while an explicit ``null`` raises -> 422."""
        if value is None:
            raise ValueError(
                f"{info.field_name} cannot be cleared; omit the field to "
                "leave it unchanged"
            )
        return value


class RewardUpdateRequest(BaseModel):
    """Body for PUT /api/v1/rewards/{reward_id}."""

    data: RewardUpdateData


class RewardResponse(BaseModel):
    """A single gym_rewards row.

    ``image_url`` / ``price_label`` are never None: both columns are NOT
    NULL (writers fill the platform default image / a required label
    before insert), mirroring how ``GymClassResponse.image_url`` is typed
    ``str``, not ``str | None``.
    """

    reward_id: UUID
    gym_id: UUID
    title: str
    point_cost: int
    image_url: str
    price_label: str
    is_active: bool
    created_at: datetime


class RewardListResponse(BaseModel):
    """List of rewards."""

    items: list[RewardResponse]


class RedemptionRequest(BaseModel):
    """Body for POST /api/v1/rewards/{reward_id}/redeem."""

    member_id: UUID


class RedeemForMemberRequest(BaseModel):
    """Body for POST /api/v1/rewards/{reward_id}/redeem-for-member."""

    member_id: UUID
    override: bool = False


class RedemptionResponse(BaseModel):
    """A single member_reward_redemptions row (full redemption result)."""

    redemption_id: UUID
    member_id: UUID
    reward_id: UUID
    gym_id: UUID
    point_cost: int
    requested_at: datetime
    status: RewardRedemptionStatus
    resolved_at: datetime | None
    points_balance_after: int


class RedemptionTransitionResponse(BaseModel):
    """Response for approve / reject admin transitions."""

    redemption_id: UUID
    status: RewardRedemptionStatus
    resolved_at: datetime
    points_balance_after: int | None = None


class RedemptionHistoryItem(BaseModel):
    """A single redemption joined with reward fields.

    ``image_url`` / ``price_label`` are joined straight off ``gym_rewards``
    (a plain, always-matching JOIN — see ``redemption_history.sql``), so
    they're never None, same as ``RewardResponse``.
    """

    redemption_id: UUID
    reward_id: UUID
    title: str
    image_url: str
    price_label: str
    point_cost: int
    requested_at: datetime
    status: RewardRedemptionStatus


class RedemptionHistoryResponse(BaseModel):
    """A member's reward redemption history."""

    items: list[RedemptionHistoryItem]


class PendingRedemptionItem(BaseModel):
    """One row from the gym-wide pending redemption queue.

    ``reward_image_url`` joins straight off ``gym_rewards`` (a plain JOIN —
    ``list_pending_redemptions.sql`` — the reward row always exists, even a
    soft-deleted one), so it's never None, same as ``RewardResponse``.
    """

    redemption_id: UUID
    member_id: UUID
    member_name: str
    reward_title: str
    reward_image_url: str
    point_cost: int
    requested_at: datetime


class PendingRedemptionListResponse(BaseModel):
    """Gym-wide pending redemption queue (paginated)."""

    items: list[PendingRedemptionItem]
    total: int
