from datetime import date
from enum import StrEnum
from uuid import UUID

from pydantic import computed_field

from . import SeedModel


class MembershipDbStatus(StrEnum):
    """Raw membership status as derived by the DB view."""

    active = "active"
    frozen = "frozen"
    cancelled = "cancelled"
    ended = "ended"


class MemberMembershipCreate(SeedModel):
    item_id: UUID
    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    start_date: date
    end_date: date | None = None
    cancel_date: date | None = None
    last_paid_date: date | None = None
    next_due_date: date | None = None
    prorate: bool = True
    total_price: int

    discount_ids: list[UUID] | None = None
    stripe_item_id: str | None = None

    def to_insert_dict(self) -> dict:
        data = super().to_insert_dict()
        data.pop("status", None)
        return data

    @computed_field
    @property
    def status(self) -> MembershipDbStatus:
        """Approximate status for data generation.

        Freeze is account-level (user_gym_profiles), not membership-level,
        so this computed field cannot derive frozen status. The DB view
        member_memberships_status is the authoritative source.
        """
        today = date.today()
        if self.cancel_date is not None and self.cancel_date <= today:
            return MembershipDbStatus.cancelled
        if self.end_date is not None and self.end_date <= today:
            return MembershipDbStatus.ended
        return MembershipDbStatus.active
