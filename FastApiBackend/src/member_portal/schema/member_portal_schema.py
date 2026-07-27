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

from datetime import date, datetime, time
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
        gym_address: The gym's street address, when set — free text the app
            shows for directions.
        gym_rank_enabled: Whether the gym runs a rank ladder at all
            (``gyms.is_rank_enabled``). False hides every rank surface.
        gym_has_rewards: Whether the gym has at least one ACTIVE reward — the
            same set ``GET …/rewards`` serves the member. Derived from data,
            never a toggle.
        gym_has_videos: Whether the gym's video feed would serve at least one
            video — the same served predicate ``GET …/videos`` pages over
            (enriched AND accepted, owner section or latest completed run).
            Derived from data, never a toggle.
        first_name: The member's first name.
        last_name: The member's last name.
        photo_url: The member's photo, when set.

    The three capability flags ride the IDENTITY read rather than the profile
    read because the client uses them to decide which BOTTOM NAV TABS exist:
    identity is fetched once at boot and cached, so the tab bar is right at
    first paint and survives offline. They are required (no default) on
    purpose — a missing column must fail loudly rather than silently hide a
    tab the gym actually offers.
    """

    member_id: UUID
    gym_id: UUID
    gym_name: str
    gym_logo_url: str | None = None
    gym_address: str | None = None
    gym_rank_enabled: bool
    gym_has_rewards: bool
    gym_has_videos: bool
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


class MemberPortalPromotion(BaseModel):
    """The member's most recent rank change, when it was a PROMOTION.

    This is what the app's promotion animation runs on. It shows the
    animation ONCE per new promotion, driven by its own local "promotion
    watermark" (the same seed-silently-on-null pattern as the existing
    celebration watermark), so the server's job is only to answer *has the
    member just moved up, and what did BOTH belts look like* — the client
    never has to remember or infer a previous rank.

    **Only a real promotion reaches here.** ``member_activities`` records
    every rank change faithfully — staff corrections, demotions and
    unassignments included — but the copy reads "You've been promoted", so
    the server surfaces a change only when the new leaf ranks strictly ABOVE
    the old one (a higher main rank on the gym's ladder, or a higher
    sub-index within the same main rank). A demotion, a lateral correction,
    an unassignment, or a change too thin to prove all serialize as ``null``,
    indistinguishable from "this member has never been promoted", and the app
    simply does not celebrate. Only the newest change is ever considered — a
    promotion later corrected downward stays buried rather than
    re-celebrating a belt the member no longer holds.

    **Decoupled from any class.** Promotions are staff-driven from the
    ready-to-promote board, minutes to days after a class and often in bulk,
    so there is no honest way to attribute one to a specific attendance.
    Nothing here references a class, and the copy reads "You've been
    promoted", never "that class promoted you".

    Attributes:
        activity_id: The ``member_activities`` row this describes — THE
            watermark key. An opaque, immutable, unique id is what the client
            compares against its stored watermark; a timestamp would be a
            weaker key (two rows can share an instant, and clock / precision
            differences across the wire make equality fragile).
        promoted_at: When the change was recorded, UTC — for display and
            ordering only, never as the watermark.
        old_rank_name: The display name of the leaf the member came FROM
            (``Blue Belt`` / ``Blue Belt · 2 Stripes``). ``None`` when there
            was no previous leaf — the member's first assignment, or the
            gym's lowest-rank backfill.
        new_rank_name: The display name of the leaf the member moved TO. The
            field stays nullable for wire compatibility, but a promotion
            always has a TO leaf — an unassignment never surfaces at all — so
            in practice it is present whenever the block is.
        old_image_url: The belt image of the FROM leaf, snapshotted at the
            moment of the change (the source columns are user-writable, so a
            live lookup would let new belt art rewrite an old promotion).
            ``None`` when there was no previous leaf, when that leaf carried
            no image, or on a row written before the payload carried images —
            the client falls back to its themed belt.
        new_image_url: The belt image of the TO leaf, same snapshot rule.

    A note on scope: only the FROM side is genuinely optional. A first
    assignment — staff giving a rank-less member their first belt, or the
    gym's lowest-rank backfill — has no leaf to have come from, so it arrives
    with the old side null and the app renders an arrival rather than an
    animation out of nothing.
    """

    activity_id: UUID
    promoted_at: datetime
    old_rank_name: str | None = None
    new_rank_name: str | None = None
    old_image_url: str | None = None
    new_image_url: str | None = None


class MemberPortalProfile(BaseModel):
    """One member's own profile — the app's home screen payload.

    Carries the member's identity, contact block, retention stats (points
    balance, class streak, THIS WEEK's attended weekdays, last class, videos
    watched), rank progress, their membership cards, their recent / pending
    reward redemptions, and their latest rank change. There is no separate
    points-balance, rank or promotion endpoint: they all live here
    (``retention.points_balance`` / ``rank`` / ``latest_promotion``).

    ``retention.current_week_attended_weekdays`` is the profile's week strip —
    SUNDAY-FIRST indices over the streak's own gym-local week, so a gym with
    ranks disabled can make the streak the screen's centrepiece without a
    second call to build seven dots (see ``BillingRetention``).

    ``latest_promotion`` rides this payload rather than a route of its own
    because the app already loads the profile on the screen that celebrates —
    a dedicated round trip would buy nothing. ``None`` for a member who has
    never had a rank change.
    """

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None
    personal_info: BillingPersonalInfo
    retention: BillingRetention
    rank: BillingRank | None = None
    latest_promotion: MemberPortalPromotion | None = None
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
