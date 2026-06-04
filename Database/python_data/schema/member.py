from datetime import date, datetime
from uuid import UUID

from . import SeedModel


class MemberCreate(SeedModel):
    """Unified identity + billing/contact row on the single `members` table.

    Core identity (name, email, points, rank) is client-writable. The merged
    contact / freeze / linkage / Stripe billing columns are written by
    service_role only and stay NULL for engagement-only members who have no
    billing. Mirrors the original CRM's single user_gym_profiles table.

    The seed creates the identity shell via the backend `POST /members`
    (which assigns member_id and creates no Stripe customer), then sets the
    billing columns: contact via a service-role UPDATE, and the Stripe
    customer + card via `PUT /members/{id}/card`. The overdue-member path
    inserts a complete row (with a real Stripe customer made under a test
    clock) directly.
    """

    member_id: UUID
    user_id: UUID | None = None
    gym_id: UUID
    last_class: datetime | None = None
    first_name: str
    last_name: str
    email: str | None = None
    points_balance: int = 0
    current_rank_id: UUID | None = None

    # Contact / freeze / linkage / Stripe billing (service_role-written only;
    # NULL for engagement-only members).
    photo_url: str | None = None
    phone: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
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
