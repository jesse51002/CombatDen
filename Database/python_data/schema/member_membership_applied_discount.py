from datetime import date
from uuid import UUID

from . import SeedModel
from .member_membership import StripeSyncStatus

__all__ = [
    "MemberMembershipAppliedDiscountCreate",
]


class MemberMembershipAppliedDiscountCreate(SeedModel):
    """Applied-discount row: one discount frozen onto one membership
    (item_id) at apply-time, referencing the immutable gym_discount_values
    version (value_id) it was applied at.

    The discount's values are reached via value_id -> gym_discount_values ->
    gym_discounts (the value_id is the provenance / version tag). end_date and
    stripe_coupon_id are sync writebacks — null until the sync resolves them.
    Linked (family) discounts are per-plan pricing, not applied here.
    """

    applied_discount_id: UUID
    item_id: UUID
    member_id: UUID
    gym_id: UUID
    value_id: UUID
    end_date: date | None = None
    stripe_coupon_id: str | None = None
    stripe_sync_status: StripeSyncStatus = StripeSyncStatus.not_added
