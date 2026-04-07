from enum import StrEnum
from typing import Optional
from uuid import UUID

from pydantic import model_validator

from . import SeedModel


class DiscountType(StrEnum):
    """Gym discount type."""

    preset = "preset"
    custom = "custom"
    family = "family"


class GymDiscountCreate(SeedModel):
    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    discount_active: bool = True
    percentage_off: Optional[float] = None
    dollar_off: Optional[int] = None
    membership_plan_id: Optional[UUID] = None
    family_discount_num: Optional[int] = None
    duration: str
    duration_in_months: Optional[int] = None
    is_deleted: bool = False
    stripe_coupon_id: Optional[str] = None

    @model_validator(mode="after")
    def validate_discount_fields(self) -> "GymDiscountCreate":
        has_pct = self.percentage_off is not None
        has_dollar = self.dollar_off is not None
        if has_pct == has_dollar:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set"
            )
        is_family = self.discount_type == DiscountType.family
        has_plan = self.membership_plan_id is not None
        has_num = self.family_discount_num is not None
        if is_family and (not has_plan or not has_num):
            raise ValueError(
                "family discounts require membership_plan_id and family_discount_num"
            )
        if not is_family and (has_plan or has_num):
            raise ValueError(
                "membership_plan_id and family_discount_num are only for family discounts"
            )
        if self.duration == "repeating" and self.duration_in_months is None:
            raise ValueError(
                "duration_in_months is required when duration is 'repeating'"
            )
        if self.duration != "repeating" and self.duration_in_months is not None:
            raise ValueError(
                "duration_in_months must be None when duration is not 'repeating'"
            )
        return self
