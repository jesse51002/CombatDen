from datetime import date, datetime
from uuid import UUID

from pydantic import field_validator

from . import SeedModel


class MemberCreate(SeedModel):
    """Unified identity + billing/contact row on the single `members` table.

    Core identity (name, email, points, rank) is client-writable. The merged
    contact / freeze / linkage / Stripe billing columns are written by
    service_role only and stay NULL for engagement-only members who have no
    billing. Mirrors the original CRM's single user_gym_profiles table.

    There is no `user_id` FK — a member's self-access is a verified Supabase
    auth account whose email matches this row's `email` (compared lowercase).

    The seed creates the identity shell via the backend `POST /members`
    (which assigns member_id and creates no Stripe customer), then sets the
    billing columns: contact via a service-role UPDATE, and the Stripe
    customer + card via `PUT /members/{id}/card`. The overdue-member path
    inserts a complete row (with a real Stripe customer made under a test
    clock) directly.
    """

    member_id: UUID
    gym_id: UUID
    last_class: datetime | None = None
    first_name: str
    last_name: str
    email: str | None = None
    points_balance: int = 0
    current_rank_id: UUID | None = None
    # Leaf position within current_rank_id's main rank (NULL when that rank has
    # sub_rank_count = 0). Only the ranks endpoints write it after creation.
    current_sub_index: int | None = None

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
    stripe_customer_id: str | None = None
    stripe_sub_id_month: str | None = None
    stripe_payment_method_id: str | None = None
    payment_type: str | None = None
    card_brand: str | None = None
    card_last_four: str | None = None
    card_exp_month: int | None = None
    card_exp_year: int | None = None
    total_monthly_recurring_price: int = 0

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str | None) -> str | None:
        """Identity now links purely by verified email (no more user_id) —
        normalize to lowercase so seeded rows match the auth account exactly."""
        return v.lower() if v is not None else v
