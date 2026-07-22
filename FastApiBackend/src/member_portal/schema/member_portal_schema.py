"""Pydantic schemas for the member-facing portal surface.

Deliberately a THIN, member-appropriate contract rather than the CRM's
``MemberBillingDetailResponse``: the mobile app is a second consumer, and the
CRM detail carries staff-facing concepts (authorization rosters, who-pays-for-
whom, ``on_outdated_price``, the aggregate recurring price) that a member has
no use for. The per-block sub-models are REUSED from
``members_billing_schema`` so the two surfaces can never disagree about what a
rank, a membership card, or a retention block looks like.

None of these models carries an ``is_member`` / ``ignore_warnings`` style
field: gate semantics are never client-selectable on a member-facing route.
"""

from datetime import date, time
from uuid import UUID

from pydantic import BaseModel

from src.members.schema.members_billing_schema import (
    BillingMembershipInfo,
    BillingPersonalInfo,
    BillingRank,
    BillingRetention,
    BillingRewardCard,
    PendingRedemptionCard,
)


class MemberPortalIdentity(BaseModel):
    """One member row the caller's verified email resolves to.

    Attributes:
        member_id: The member row — every other member-portal route takes
            this explicitly; it is never derived from the JWT.
        gym_id: The gym that member belongs to. Pass it back on every
            gym-scoped route so ``verify_member_self`` can scope the match.
        gym_name: The gym's display name (a family may span gyms).
        gym_logo_url: The gym's logo, when set.
        first_name: The member's first name.
        last_name: The member's last name.
        photo_url: The member's photo, when set.
    """

    member_id: UUID
    gym_id: UUID
    gym_name: str
    gym_logo_url: str | None = None
    first_name: str
    last_name: str
    photo_url: str | None = None


class MemberPortalIdentityListResponse(BaseModel):
    """The caller's member rows across every gym.

    A list, never a single object: ``members.email`` has no uniqueness
    constraint by design, so a parent's address matches every member row in
    the family.
    """

    members: list[MemberPortalIdentity]


class MemberPortalProfile(BaseModel):
    """One member's own profile — the app's home screen payload.

    Carries the member's identity, contact block, retention stats (points
    balance, class streak, last class, videos watched), rank progress, their
    membership cards, and their recent / pending reward redemptions. There is
    no separate points-balance or rank endpoint: both live here
    (``retention.points_balance`` / ``rank``).
    """

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None
    personal_info: BillingPersonalInfo
    retention: BillingRetention
    rank: BillingRank | None = None
    memberships: list[BillingMembershipInfo] = []
    recently_redeemed_rewards: list[BillingRewardCard] = []
    pending_redemptions: list[PendingRedemptionCard] = []


class MemberPortalSignupRequest(BaseModel):
    """Body for the member's own class reservation.

    ``member_id`` / ``gym_id`` are deliberately NOT in the body — they are
    path parameters the gate has already verified, so a client cannot reserve
    for somebody else by editing a JSON field.

    ``(occurrence_date, occurrence_time)`` is the occurrence's full ORIGINAL
    slot (the owning schedule version's pre-exception date + time), exactly
    as the schedule board returns it.
    """

    class_id: UUID
    occurrence_date: date
    occurrence_time: time
