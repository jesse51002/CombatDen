from datetime import date, datetime
from typing import Optional
from uuid import UUID

from . import SeedModel


class UserGymProfileCreate(SeedModel):
    crm_user_id: UUID
    user_id: Optional[UUID] = None
    gym_id: UUID
    last_class: Optional[datetime] = None
    first_name: str
    last_name: str
    photo_url: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    emergency_contact_email: Optional[str] = None
    points_balance: int = 0
    freeze_start_date: Optional[date] = None
    freeze_end_date: Optional[date] = None
    account_linked_to_id: Optional[UUID] = None
    linked_discount_id: Optional[UUID] = None
    stripe_customer_id: Optional[str] = None
    stripe_sub_id_month: Optional[str] = None
    stripe_payment_method_id: Optional[str] = None
    payment_type: Optional[str] = None
    card_brand: Optional[str] = None
    card_last_four: Optional[str] = None
    card_exp_month: Optional[int] = None
    card_exp_year: Optional[int] = None
