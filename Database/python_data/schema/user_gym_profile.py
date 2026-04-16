from datetime import date, datetime
from uuid import UUID

from . import SeedModel


class UserGymProfileCreate(SeedModel):
    crm_user_id: UUID
    user_id: UUID | None = None
    gym_id: UUID
    last_class: datetime | None = None
    first_name: str
    last_name: str
    photo_url: str | None = None
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    points_balance: int = 0
    freeze_start_date: date | None = None
    freeze_end_date: date | None = None
    account_linked_to_id: UUID | None = None
    linked_discount_id: UUID | None = None
    stripe_customer_id: str | None = None
    stripe_sub_id_month: str | None = None
    stripe_payment_method_id: str | None = None
    payment_type: str | None = None
    card_brand: str | None = None
    card_last_four: str | None = None
    card_exp_month: int | None = None
    card_exp_year: int | None = None
    total_monthly_recurring_price: int = 0
