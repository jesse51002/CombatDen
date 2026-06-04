from datetime import date
from uuid import UUID

from pydantic import model_validator

from . import SeedModel
from .gym_discount import DiscountDurationUnit, DiscountMode, DiscountType

__all__ = [
    "DiscountDurationUnit",
    "DiscountMode",
    "MemberMembershipAppliedDiscountCreate",
]


class MemberMembershipAppliedDiscountCreate(SeedModel):
    """Immutable applied-discount snapshot: one discount frozen onto one
    membership (item_id) at apply-time.

    Regular (preset/custom) rows carry source_discount_id (provenance to the
    gym_discounts preset). Linked rows carry linked_discount_planid +
    linked_discount_num (and no source preset). end_date and stripe_coupon_id
    are sync writebacks — null until the sync resolves them.
    """

    applied_discount_id: UUID
    item_id: UUID
    member_id: UUID
    gym_id: UUID
    discount_type: DiscountType
    source_discount_id: UUID | None = None
    linked_discount_planid: UUID | None = None
    linked_discount_num: int | None = None
    discount_name: str
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode
    end_date: date | None = None
    stripe_coupon_id: str | None = None

    @model_validator(mode="after")
    def validate_snapshot_fields(self) -> "MemberMembershipAppliedDiscountCreate":
        has_pct = self.percentage_off is not None
        has_dollar = self.dollar_off is not None
        if has_pct == has_dollar:
            raise ValueError("Exactly one of percentage_off or dollar_off must be set")

        is_linked = self.discount_type == DiscountType.linked
        has_plan = self.linked_discount_planid is not None
        has_num = self.linked_discount_num is not None
        has_source = self.source_discount_id is not None
        if is_linked:
            if not has_plan or not has_num:
                raise ValueError(
                    "linked snapshots require linked_discount_planid and linked_discount_num"
                )
            if has_source:
                raise ValueError("linked snapshots must not carry source_discount_id")
        else:
            if not has_source:
                raise ValueError("regular snapshots require source_discount_id")
            if has_plan or has_num:
                raise ValueError(
                    "linked_discount_planid/linked_discount_num are only for linked snapshots"
                )
        return self
