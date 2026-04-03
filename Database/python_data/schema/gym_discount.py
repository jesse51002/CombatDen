from datetime import date
from typing import Literal, Optional
from uuid import UUID

from pydantic import model_validator

from . import SeedModel


class GymDiscountCreate(SeedModel):
    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: Literal["membership", "custom"]
    discount_active: bool = True
    percentage_off: Optional[float] = None
    dollar_off: Optional[float] = None
    end_date: Optional[date] = None
    is_deleted: bool = False

    @model_validator(mode="after")
    def exactly_one_discount_type(self) -> "GymDiscountCreate":
        has_pct = self.percentage_off is not None
        has_dollar = self.dollar_off is not None
        if has_pct == has_dollar:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set"
            )
        return self
