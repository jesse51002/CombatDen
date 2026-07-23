"""Pydantic schemas for the member-facing portal surface.

A projection of the CRM's ``MemberBillingDetailResponse`` down to the member's
OWN data. It is thinner than the CRM detail in that it drops the top-level
STAFF-only blocks — the authorized-payer roster and the who-this-member-pays-
for grouping the front desk uses to manage a family's billing. It is NOT a
field-stripped variant of the per-block models: those sub-models
(``BillingMembershipInfo``, ``BillingRank``, ``BillingRetention``,
``BillingRewardCard``, ``PendingRedemptionCard``) are REUSED verbatim from
``members_billing_schema`` so the two surfaces can never disagree about what a
membership card or a rank looks like. Consequently each membership card here
carries the same per-membership fields the CRM shows — including
``paid_by_member_id``, ``current_active_price``, ``on_outdated_price``, and the
applied discounts — scoped strictly to the caller's own rows (a member seeing
their own payer and price is fine; what they never get is another member's).

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


class RankProgressPoint(BaseModel):
    """One point in the member's rank-progress series (the profile graph).

    Attributes:
        date: The gym-local day the activity happened (bucketed in the gym's
            own timezone, like the streak and last-class reads).
        classes_into_rank: Classes accrued toward the next rank at this point —
            reset to 0 at each promotion (a ``rank_changed`` marker) and capped
            at ``classes_needed``.
        classes_needed: Classes required to reach the next rank — the member's
            CURRENT per-step threshold from the gym's live rank ladder (the same
            derivation the profile's rank block uses: an even split of
            ``classes_to_next_major`` across the effective sub-positions, else
            the full major threshold). Constant across the series; historical
            threshold changes are approximated by today's value.
    """

    date: date
    classes_into_rank: int
    classes_needed: int


class MemberRankProgressResponse(BaseModel):
    """The member's rank-progress series — one point per activity event.

    Walked chronologically from the member's ``member_activities``: each
    ``rank_changed`` resets the counter to 0, each ``class_attended`` after it
    increments the counter by one (capped at ``classes_needed``). ``points`` is
    an empty list (a valid 200) when the member holds no rank or the gym has
    ranks disabled.
    """

    points: list[RankProgressPoint]


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
