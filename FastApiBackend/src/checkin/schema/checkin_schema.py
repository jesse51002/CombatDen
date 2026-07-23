"""Pydantic models for the checkin domain."""

from datetime import date, datetime, time
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field
from schema.membership_plan import PlanType

from src.checkin.schema.cycle_counts_schema import MembershipUsage


class CheckinWarning(StrEnum):
    """A gate condition that would block a kiosk check-in.

    The gate evaluates these once per (member, occurrence). ``is_member``
    decides what they mean:

    * ``is_member=True`` (kiosk / member self-check-in) — a blocking condition
      *rejects* the check-in (returned as the response ``skip_reason``, nothing
      written).
    * ``is_member=False`` (staff / admin) — the same conditions come back as
      ``warnings`` that hold the check-in for confirmation
      (``requires_confirmation``, nothing written) unless ``ignore_warnings``
      overrides, which records through them.

    Attributes:
        no_membership: The member has no active membership; an overridden staff
            check-in attributes with NULL ``plan_id`` / ``item_id``.
        out_of_classes: The attributed membership's punch-card is depleted
            (an overridden staff check-in over-draws it).
        ineligible_plan: The attributed membership's plan is not in the class's
            ``allowed_plan_ids``.
        over_capacity: The room is at ``max_capacity`` for this occurrence (the
            headcount gate).
        unsigned_waiver: The member has an unsigned required waiver — one of
            their CURRENT (active/frozen) memberships' plans requires a waiver
            they have not signed at a version >= its re-sign floor (the same
            set the member-detail Waivers section shows). Reservations are
            deliberately NOT gated — only the check-in.
    """

    no_membership = "no_membership"
    out_of_classes = "out_of_classes"
    ineligible_plan = "ineligible_plan"
    over_capacity = "over_capacity"
    unsigned_waiver = "unsigned_waiver"


class GateEvaluation(BaseModel):
    """The single gate evaluation reused by both check-in modes.

    Built once per (member, occurrence) by ``CheckinMemberGate`` and read by
    both the kiosk (strict) and staff (always-record) paths.

    Attributes:
        reasons: Blocking conditions relative to the attributed "best available"
            membership (``forced``) — these become a staff check-in's warnings.
        strict: The best eligible membership with remaining capacity, or None
            (the kiosk gate blocks when this is None).
        forced: The best available membership ignoring eligibility / capacity,
            or None when the member has no active membership (the staff
            attribution target).
    """

    reasons: set[CheckinWarning] = Field(default_factory=set)
    strict: MembershipUsage | None = None
    forced: MembershipUsage | None = None

    @property
    def blocked(self) -> bool:
        """Whether the strict kiosk gate rejects this member.

        Blocked iff the room is full, a required waiver is unsigned, the
        member has no membership, or no eligible covering membership has
        remaining capacity (``strict`` None).
        """
        return (
            CheckinWarning.over_capacity in self.reasons
            or CheckinWarning.unsigned_waiver in self.reasons
            or self.forced is None
            or self.strict is None
        )


class CheckinRequest(BaseModel):
    """Body for POST /api/v1/checkin.

    The occurrence is addressed by ``class_id`` + ``occurrence_date`` +
    ``occurrence_time`` — always the occurrence's ORIGINAL slot (the owning
    schedule version's pre-exception date + time), never its
    effective/rescheduled slot; the backend resolves the occurrence against
    the class's schedule versions + exceptions. A class may occur several
    times on one day, so the date alone never identifies an occurrence — the
    time is required. Occurrences are computed, never stored — there is no
    materialization step.

    ``is_member`` selects the gate:

    * ``True`` — the member self-checks-in (kiosk). The strict gate applies: if
      no eligible covering membership has remaining capacity, the member is out
      of classes, the room is full, or the plan is ineligible, the check-in is
      rejected (``log_id = null`` + a ``skip_reason``, nothing written).
    * ``False`` (default — staff / admin) — a clean check-in is recorded. But if
      the gate raises any warning (no membership / out of classes / ineligible /
      over capacity), the check-in is NOT recorded: the response comes back with
      ``requires_confirmation = true`` and the ``warnings``, so staff can decide.
      To go ahead anyway, resend with ``ignore_warnings = true`` — then it is
      recorded (attributed to the best available membership, NULL plan/item when
      none) with the warnings surfaced.

    ``ignore_warnings`` only applies to a staff check-in (``is_member = false``);
    a kiosk check-in is never overridable.
    """

    member_id: UUID
    gym_id: UUID
    class_id: UUID
    occurrence_date: date
    occurrence_time: time
    is_member: bool = False
    ignore_warnings: bool = False


class ResolvedClass(BaseModel):
    """A resolved class occurrence — the input to a per-member check-in.

    Produced by ``CheckinClassResolver.resolve`` once per occurrence, then
    reused to check in one or many members (batch). Purely a read: resolving
    an occurrence never writes anything — occurrences are always computed
    from the class's schedule versions + exceptions, never stored.

    Attributes:
        class_id: The owning class.
        gym_id: The owning gym.
        occurrence_date: The occurrence's ORIGINAL date (the owning schedule
            version's pre-exception slot) — the same date the caller passed
            to ``resolve``. Used by the capacity gate to read the
            signed-up-or-attended union for this occurrence, and stored on
            ``member_attendance`` as part of the occurrence's identity key.
        original_time: The owning schedule version's pre-exception slot
            time — the other half of the occurrence's identity key, the same
            time the caller passed to ``resolve`` (a class may occur several
            times per day, so this is what disambiguates the slot), stored
            alongside ``occurrence_date`` on the attendance row.
        occurred_at: UTC, timezone-aware EFFECTIVE start instant of the
            occurrence (exceptions applied) — denormalized onto the
            attendance row for streak / cycle-count / last-class window SQL.
        points_worth: Points awarded for attending this class.
        class_name: The class's display name (snapshotted into the activity).
        max_capacity: Effective room capacity (the instance exception's
            ``new_max_capacity`` if set, else the class's ``max_capacity``);
            None = unlimited.
        allowed_plan_ids: Plans permitted to attend (None = all). Carried for
            context; the eligibility gate queries this in SQL.
        instructor_id: Effective instructor for the occurrence (None = none).
        duration_minutes: Effective length of the occurrence in minutes.
    """

    class_id: UUID
    gym_id: UUID
    occurrence_date: date
    original_time: time
    occurred_at: datetime
    points_worth: int
    class_name: str
    max_capacity: int | None
    allowed_plan_ids: list[UUID] | None
    instructor_id: UUID | None
    duration_minutes: int


class CheckinMembershipBreakdown(BaseModel):
    """Usage breakdown for one of the member's active memberships.

    Attributes:
        item_id: The membership row (the bucket this usage belongs to).
        plan_id: The membership plan.
        plan_type: Trial, one_time, or recurring.
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes used this cycle (post-checkin for the
            charged membership).
        classes_remaining: Classes left (None = unlimited).
        is_eligible: Whether this plan covers the checked-in class.
        renew_date: Next renewal / due date (recurring plans; None
            otherwise).
        end_date: Membership expiry date (trial / one_time plans; None
            otherwise).
    """

    item_id: UUID
    plan_id: UUID
    plan_type: PlanType
    class_count: int | None
    classes_used: int
    classes_remaining: int | None
    is_eligible: bool
    renew_date: date | None
    end_date: date | None


class CheckinResponse(BaseModel):
    """Response for POST /api/v1/checkin.

    The outcome depends on ``is_member`` (see ``CheckinRequest``):

    * A kiosk check-in (``is_member=True``) that hits the gate is *rejected* —
      ``log_id`` / ``chosen_plan_id`` / ``chosen_item_id`` are ``None``, nothing
      is written, and ``skip_reason`` says why.
    * A staff check-in (``is_member=False``) that hits a warning is NOT recorded
      unless ``ignore_warnings`` was set — ``log_id`` is null,
      ``requires_confirmation`` is true, and ``warnings`` say why, so staff can
      resend with ``ignore_warnings=true``. A clean (or overridden) staff
      check-in IS recorded — ``log_id`` set, warnings surfaced when overridden,
      NULL plan/item when the member has no membership.

    The ``memberships`` breakdown explains the decision either way.

    Attributes:
        log_id: The attendance row. None when a kiosk check-in was rejected.
        member_id: The member who checked in.
        class_id: The class the occurrence belongs to.
        already_checked_in: True when an attendance row already existed
            for this (member, class instance) — the check-in was
            idempotent and no capacity was consumed.
        chosen_plan_id: The plan charged. None when rejected or when a staff
            check-in had no membership to attribute to.
        chosen_item_id: The membership row charged. None when rejected or when a
            staff check-in had no membership to attribute to.
        points_awarded: The class's ``points_worth`` this check-in is worth —
            actually added to the balance on a newly-recorded check-in (membership
            or not), or merely REPORTED (balance untouched) on an idempotent
            repeat so it can still be shown; 0 on a rejection (kiosk skip) and
            also 0 on a staff check-in held for ``requires_confirmation`` — in
            both cases nothing was written. Use ``already_checked_in`` to tell a
            fresh award apart from a repeat's echo.
        skip_reason: Why a kiosk check-in was rejected (no attendance written);
            None when recorded or an idempotent repeat.
        warnings: Gate conditions surfaced to staff — the reasons this check-in
            needs confirmation (when ``requires_confirmation``), or the conditions
            it was recorded through (when overridden with ``ignore_warnings``).
            Empty on a kiosk check-in and on a clean staff check-in.
        requires_confirmation: True when a staff check-in was NOT recorded because
            of ``warnings`` and no ``ignore_warnings`` override — resend with
            ``ignore_warnings=true`` to record it. Always False on a kiosk
            check-in, a clean check-in, or a repeat.
        class_streak_weeks: The member's current weekly attendance streak AFTER
            this check-in — the same value ``GET /api/v1/streak`` returns, folded
            into the check-in response so the caller needn't make a second call.
            0 when the check-in was not recorded (a rejection / needs-confirmation).
        current_week_days: The member's current gym-local week attendance strip
            AFTER this check-in — a length-7 list, index 0 = Monday .. 6 = Sunday
            (Monday-first), each ``True`` when the member attended a class on that
            weekday of the CURRENT gym-local week. The same value the strip on
            ``GET /api/v1/streak`` carries, folded in alongside
            ``class_streak_weeks``. All ``False`` when the check-in was not
            recorded (a rejection / needs-confirmation).
        memberships: Breakdown of the member's active memberships.
    """

    log_id: UUID | None
    member_id: UUID
    class_id: UUID
    already_checked_in: bool
    chosen_plan_id: UUID | None = None
    chosen_item_id: UUID | None = None
    points_awarded: int = 0
    skip_reason: CheckinWarning | None = None
    warnings: list[CheckinWarning] = []
    requires_confirmation: bool = False
    class_streak_weeks: int = 0
    current_week_days: list[bool] = Field(default_factory=lambda: [False] * 7)
    memberships: list[CheckinMembershipBreakdown] = []


class CheckinRemoveResponse(BaseModel):
    """Result of removing one member's check-in from an occurrence.

    The full reversal of a check-in, scoped to one member (delete attendance,
    claw back points, reverse the pack auto-end, drop a feed activity) — the
    occurrence itself is kept.

    Attributes:
        removed: True when an attendance row was deleted; False when the
            member was not checked in to that occurrence.
        points_reverted: The class's ``points_worth`` reversed off the member's
            balance (floored at 0 by the balance CHECK); 0 when nothing removed.
        membership_unended: The pack whose auto-end was reversed (its ``end_date``
            cleared because the removal dropped it back below capacity), else None.
    """

    removed: bool
    points_reverted: int = 0
    membership_unended: UUID | None = None


class Attendee(BaseModel):
    """One member who signed up for, attended, or both, a class occurrence.

    Attributes:
        member_id: The member.
        full_name: The member's display name.
        signed_up: True when the member has a ``class_signups`` row for this
            occurrence.
        attended: True when the member has a ``member_attendance`` row for
            this occurrence.
        log_id: The attendance row. None when not attended (signed-up-only).
        plan_id: The plan the attendance was attributed to. None when not
            attended, or a no-membership staff check-in.
        item_id: The membership row the attendance was attributed to. None
            when not attended, or a no-membership staff check-in.
    """

    member_id: UUID
    full_name: str
    signed_up: bool
    attended: bool
    log_id: UUID | None = None
    plan_id: UUID | None = None
    item_id: UUID | None = None


class AttendeeListResponse(BaseModel):
    """Response for GET /api/v1/checkin/attendees — the combined roster.

    Everyone who signed up OR attended the occurrence, each flagged. A
    signed-up-only member can appear even when nobody has checked in yet (a
    future occurrence can carry sign-ups with no attendance at all).

    Attributes:
        class_id: The class the occurrence belongs to.
        occurrence_date: The occurrence's ORIGINAL date — half of the
            identity key queried (paired with the ``occurrence_time`` query
            param; a class may occur several times per day).
        attendees: Everyone signed up or attended, ordered by name.
    """

    class_id: UUID
    occurrence_date: date
    attendees: list[Attendee]


class StreakResponse(BaseModel):
    """Response for GET /api/v1/streak.

    Attributes:
        member_id: The member the streak belongs to.
        class_streak_weeks: Consecutive gym-local weeks with at least one
            class attendance.
        current_week_days: The current gym-local week attendance strip — a
            length-7 list, index 0 = Monday .. 6 = Sunday (Monday-first), each
            ``True`` when the member attended a class on that weekday of the
            CURRENT gym-local week. All ``False`` when they have not attended
            this week.
    """

    member_id: UUID
    class_streak_weeks: int
    current_week_days: list[bool] = Field(default_factory=lambda: [False] * 7)
