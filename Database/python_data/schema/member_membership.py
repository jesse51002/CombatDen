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


class StripeSyncStatus(StrEnum):
    """The sync's confirmation of whether a row landed on Stripe.

    Mirrors the Postgres `stripe_sync_status` enum (a NOT NULL column,
    default `not_added`). The Stripe-convergence axis, orthogonal to the
    lifecycle MembershipDbStatus: `not_added` = pending (the row is asking the
    sync to add it); the sync (writeback) stamps `applied` once Stripe confirms
    and `deleted` on removal; `preview_add`/`preview_remove` are reserved for
    preview-staging. Shared by member_memberships and
    member_membership_applied_discounts.
    """

    not_added = "not_added"
    applied = "applied"
    deleted = "deleted"
    preview_add = "preview_add"
    preview_remove = "preview_remove"


class MemberMembershipCreate(SeedModel):
    item_id: UUID
    member_id: UUID
    # Who pays this membership (NOT NULL in the DB): the linked parent for a
    # family child, else the member themselves. The payment sync groups
    # memberships by this column — one subscription per payer.
    paid_by_member_id: UUID
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

    stripe_item_id: str | None = None
    stripe_sync_status: StripeSyncStatus = StripeSyncStatus.not_added

    def to_insert_dict(self) -> dict:
        data = super().to_insert_dict()
        data.pop("status", None)
        return data

    @computed_field
    @property
    def status(self) -> MembershipDbStatus:
        """Approximate status for data generation.

        Freeze is payer-level (the paid_by_member_id's freeze window on
        members), not membership-level, so this computed field cannot derive
        frozen status. The DB view member_memberships_status is the
        authoritative source.
        """
        today = date.today()
        if self.cancel_date is not None and self.cancel_date <= today:
            return MembershipDbStatus.cancelled
        if self.end_date is not None and self.end_date <= today:
            return MembershipDbStatus.ended
        return MembershipDbStatus.active
