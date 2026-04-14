from enum import StrEnum
from typing import Optional
from uuid import UUID

from . import SeedModel


class LineItemType(StrEnum):
    membership = "membership"
    custom = "custom"


class UserGymInvoiceLineItemCreate(SeedModel):
    line_item_id: str  # Stripe line item id (il_xxx); no default
    invoice_id: UUID
    gym_id: UUID
    item_type: LineItemType
    name: str
    amount: int
    stripe_product_id: Optional[str] = None
    item_id: Optional[UUID] = None  # required when item_type == membership
