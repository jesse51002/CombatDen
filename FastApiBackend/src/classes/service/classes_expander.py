"""The canonical recurrence + exception expander for the class system.

``ClassesExpander`` is the one authoritative engine that turns a class plus its
exceptions, over a date window, into the effective dated occurrences
(recurrence expanded, exceptions applied). By default cancelled occurrences are
dropped; passing ``include_cancelled=True`` instead EMITS them with
``is_cancelled=True`` (carrying the class's default time / instructor for
display) so a schedule board can show a struck-through cancelled day. Every
consumer — the versioned expander, check-in validation, reschedule checks —
imports THIS, so its semantics must stay exact. The check-in / validation
callers leave ``include_cancelled`` at its default ``False``; only the display
read path opts in.

It is PURE: no DB, no I/O, no clock. Everything is derived from the arguments,
which makes it fully unit-testable.

Recurrence + exception semantics mirror the seed generator
(``Database/python_data/generators/classes.py`` — ``_enumerate_occurrences``,
``_resolve_occurrence``, ``_weekday_short``) byte-for-byte, so seeded history
and runtime expansion can never disagree. The two deliberate differences from
the seed are the window bound (the seed bounds by ``today`` + a count cap; the
expander bounds by the caller's date window) and the ``occurred_at`` timestamp
(see ``_build`` — the seed stamps the local time as naive UTC for fake history;
the expander does a real gym-timezone -> UTC conversion).

Timezone / DST: ``occurred_at`` is built with
``datetime.combine(date, time, tzinfo=ZoneInfo(gym_tz)).astimezone(utc)``. DST
edge cases are accepted as-is via Python's default ``fold=0``:
- Spring-forward gap: a wall time that never existed (e.g. 02:30 on a US
  spring-forward day) resolves using the pre-transition (standard) offset.
- Fall-back fold: an ambiguous wall time resolves to its first (earlier)
  occurrence.
These are intentionally not special-cased — a gym scheduling a class inside the
one missing hour is vanishingly rare and the resolved instant is deterministic.
"""

import calendar
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from dateutil.relativedelta import relativedelta
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import (
    EffectiveOccurrence,
    ExpanderClass,
    ExpanderInstanceException,
    ExpanderRangeException,
)

# Weekday short names indexed by ``(date.weekday() + 1) % 7`` so Python's
# Mon=0..Sun=6 maps to sun=0..sat=6 — identical to the seed's ``DAYS`` list.
_DAY_SHORT: tuple[str, ...] = (
    "sun",
    "mon",
    "tue",
    "wed",
    "thu",
    "fri",
    "sat",
)
_INSTRUCTOR_SUFFIX = "_instructor_id"


class ClassesExpander:
    """Expands one class + its exceptions into effective dated occurrences.

    Stateless and constructor-free: a single shared instance is safe to reuse.
    """

    def expand(
        self,
        gym_class: ExpanderClass,
        instance_exceptions: list[ExpanderInstanceException],
        range_exceptions: list[ExpanderRangeException],
        window_start: date,
        window_end: date,
        gym_tz: str,
        include_cancelled: bool = False,
    ) -> list[EffectiveOccurrence]:
        """Yield the class's effective occurrences within the window.

        Args:
            gym_class: The class and its embedded recurring schedule.
            instance_exceptions: Single-date overrides for this class.
            range_exceptions: Date-range overrides for this class.
            window_start: First date of interest (inclusive).
            window_end: Last date of interest (inclusive).
            gym_tz: IANA timezone name of the gym (e.g. ``America/Chicago``)
                used to convert each local start time to UTC.
            include_cancelled: When False (default), cancelled occurrences are
                dropped (the check-in / validation behavior). When True, a
                cancelled occurrence is instead EMITTED with
                ``is_cancelled=True`` on its ``original_date`` using the class's
                default time / duration / instructor (for a display board).

        Returns:
            Effective occurrences sorted by ``occurred_at``. With the default
            ``include_cancelled=False`` cancelled occurrences never appear; with
            ``include_cancelled=True`` they appear flagged. An empty list is
            returned for an invalid window (``window_start > window_end``) or
            when the class's recurrence does not overlap the window at all.
        """
        if window_start > window_end:
            return []

        instance_by_date = {
            exc.original_date: exc for exc in instance_exceptions
        }
        ordered_ranges = sorted(
            range_exceptions, key=lambda exc: exc.created_at
        )

        occurrences: list[EffectiveOccurrence] = []
        for original_date in self._candidate_dates(
            gym_class, window_start, window_end
        ):
            occurrence = self._resolve(
                gym_class,
                original_date,
                instance_by_date.get(original_date),
                ordered_ranges,
                window_start,
                window_end,
                gym_tz,
                include_cancelled,
            )
            if occurrence is not None:
                occurrences.append(occurrence)

        occurrences.sort(key=lambda occ: occ.occurred_at)
        return occurrences

    # -- recurrence enumeration ------------------------------------------

    def _candidate_dates(
        self,
        gym_class: ExpanderClass,
        window_start: date,
        window_end: date,
    ) -> list[date]:
        """Enumerate the recurrence dates that fall inside the window.

        Counting is always relative to ``start_date`` (so the modular tests
        match the seed); only emission is bounded to
        ``[max(window_start, start_date) .. min(window_end, end_date)]``.
        """
        lower = max(window_start, gym_class.start_date)
        upper = self._window_upper(gym_class, window_end)
        if lower > upper:
            return []
        if gym_class.recurring_unit == RecurringUnit.monthly:
            return self._monthly_dates(gym_class, lower, upper)
        return self._stepwise_dates(gym_class, lower, upper)

    @staticmethod
    def _window_upper(gym_class: ExpanderClass, window_end: date) -> date:
        """The effective upper bound: ``min(window_end, end_date or end)``."""
        end = gym_class.end_date if gym_class.end_date is not None else window_end
        return min(window_end, end)

    def _monthly_dates(
        self,
        gym_class: ExpanderClass,
        lower: date,
        upper: date,
    ) -> list[date]:
        """Anchored monthly dates (never day-walked, never chained).

        Each anchor is ``start_date + relativedelta(months=n*interval)`` with
        the day clamped to that month's length, so Jan 31 -> Feb 28/29 ->
        Mar 31 is always recomputed from ``start_date.day``.
        """
        interval = gym_class.recurring_interval
        start = gym_class.start_date
        out: list[date] = []
        n = 0
        while True:
            anchor = start + relativedelta(months=n * interval)
            last_day = calendar.monthrange(anchor.year, anchor.month)[1]
            occ = anchor.replace(day=min(start.day, last_day))
            if occ > upper:
                break
            if occ >= lower:
                out.append(occ)
            n += 1
        return out

    def _stepwise_dates(
        self,
        gym_class: ExpanderClass,
        lower: date,
        upper: date,
    ) -> list[date]:
        """Daily / weekly dates, walked one day at a time within the window.

        Daily fires when ``(D - start_date).days % interval == 0`` (day flags
        ignored). Weekly fires when the week index since ``start_date`` is a
        multiple of ``interval`` AND D's weekday flag is set.
        """
        interval = gym_class.recurring_interval
        start = gym_class.start_date
        is_daily = gym_class.recurring_unit == RecurringUnit.daily
        out: list[date] = []
        cursor = lower
        while cursor <= upper:
            days_from_start = (cursor - start).days
            if is_daily:
                fires = days_from_start % interval == 0
            else:
                week_index = days_from_start // 7
                fires = (
                    week_index % interval == 0
                    and self._day_flag(gym_class, cursor)
                )
            if fires:
                out.append(cursor)
            cursor += timedelta(days=1)
        return out

    # -- exception resolution --------------------------------------------

    def _resolve(
        self,
        gym_class: ExpanderClass,
        original_date: date,
        instance: ExpanderInstanceException | None,
        ordered_ranges: list[ExpanderRangeException],
        window_start: date,
        window_end: date,
        gym_tz: str,
        include_cancelled: bool,
    ) -> EffectiveOccurrence | None:
        """Resolve one candidate date against its exceptions.

        Precedence mirrors the seed's ``_resolve_occurrence``:
        an instance exception on the exact date is authoritative (range
        exceptions ignored for that date); otherwise the earliest-created
        covering range applies; otherwise the class defaults.
        """
        default_instructor = self.instructor_for(gym_class, original_date)

        if instance is not None:
            return self._resolve_instance(
                gym_class,
                original_date,
                instance,
                default_instructor,
                window_start,
                window_end,
                gym_tz,
                include_cancelled,
            )

        covering = self._covering_range(ordered_ranges, original_date)
        if covering is not None:
            if covering.is_cancelled:
                return self._cancelled_display(
                    gym_class,
                    original_date,
                    default_instructor,
                    gym_tz,
                    include_cancelled,
                    cancelling_range_id=covering.exception_id,
                )
            instructor = (
                covering.new_instructor_id
                if covering.new_instructor_id is not None
                else default_instructor
            )
            return self._build(
                original_date,
                gym_class.class_time,
                original_date,
                gym_class.class_time,
                gym_class.duration_minutes,
                instructor,
                False,
                gym_tz,
            )

        return self._build(
            original_date,
            gym_class.class_time,
            original_date,
            gym_class.class_time,
            gym_class.duration_minutes,
            default_instructor,
            False,
            gym_tz,
        )

    def _cancelled_display(
        self,
        gym_class: ExpanderClass,
        original_date: date,
        default_instructor: UUID | None,
        gym_tz: str,
        include_cancelled: bool,
        cancelling_range_id: UUID | None = None,
    ) -> EffectiveOccurrence | None:
        """Emit a cancelled occurrence for display, or drop it.

        Returns None (the default drop) unless ``include_cancelled`` is set, in
        which case the occurrence is emitted on its ``original_date`` with the
        class's default time / duration / instructor and ``is_cancelled=True``.
        ``cancelling_range_id`` is set by the caller ONLY for a range cancel
        (never an instance cancel) and carried onto the emitted occurrence.
        """
        if not include_cancelled:
            return None
        return self._build(
            original_date,
            gym_class.class_time,
            original_date,
            gym_class.class_time,
            gym_class.duration_minutes,
            default_instructor,
            False,
            gym_tz,
            is_cancelled=True,
            cancelling_range_id=cancelling_range_id,
        )

    def _resolve_instance(
        self,
        gym_class: ExpanderClass,
        original_date: date,
        instance: ExpanderInstanceException,
        default_instructor: UUID | None,
        window_start: date,
        window_end: date,
        gym_tz: str,
        include_cancelled: bool,
    ) -> EffectiveOccurrence | None:
        """Apply an authoritative single-date instance exception.

        A cancellation drops the occurrence (or, when ``include_cancelled`` is
        set, emits it flagged on its original date for display). A reschedule
        whose target falls outside the window is dropped from THIS window (the
        original date stays suppressed regardless). Overrides use explicit
        ``is not None`` checks so ``time(0, 0)`` / ``0`` are never mistaken for
        "absent". When no instructor override is given, the default is the
        ORIGINAL date's weekday instructor — a moved occurrence keeps its slot's
        instructor (the seed's deliberate choice).
        """
        if instance.is_cancelled:
            return self._cancelled_display(
                gym_class,
                original_date,
                default_instructor,
                gym_tz,
                include_cancelled,
            )

        is_rescheduled = instance.new_date is not None
        effective_date = (
            instance.new_date if is_rescheduled else original_date
        )
        if not (window_start <= effective_date <= window_end):
            return None

        class_time = (
            instance.new_class_time
            if instance.new_class_time is not None
            else gym_class.class_time
        )
        duration = (
            instance.new_duration_minutes
            if instance.new_duration_minutes is not None
            else gym_class.duration_minutes
        )
        instructor = (
            instance.new_instructor_id
            if instance.new_instructor_id is not None
            else default_instructor
        )
        return self._build(
            original_date,
            gym_class.class_time,
            effective_date,
            class_time,
            duration,
            instructor,
            is_rescheduled,
            gym_tz,
        )

    @staticmethod
    def _covering_range(
        ordered_ranges: list[ExpanderRangeException],
        when: date,
    ) -> ExpanderRangeException | None:
        """The earliest-created range covering ``when`` (inclusive).

        ``ordered_ranges`` is pre-sorted by ``created_at``, so the first match
        is the earliest-created.
        """
        for exc in ordered_ranges:
            if exc.start_date <= when <= exc.end_date:
                return exc
        return None

    # -- materialization -------------------------------------------------

    @staticmethod
    def _build(
        original_date: date,
        original_time: time,
        effective_date: date,
        class_time: time,
        duration_minutes: int,
        instructor_id: UUID | None,
        is_rescheduled: bool,
        gym_tz: str,
        is_cancelled: bool = False,
        cancelling_range_id: UUID | None = None,
    ) -> EffectiveOccurrence:
        """Materialize one resolved occurrence, computing ``occurred_at``.

        The effective local date + time is interpreted in the gym's timezone
        and converted to UTC. See the module docstring for the DST policy.
        ``original_time`` is the schedule's pre-exception default start time —
        the occurrence's identity time, distinct from the effective
        ``class_time``. ``cancelling_range_id`` is only ever non-None when a
        RANGE exception cancelled this occurrence (see ``_cancelled_display``).
        """
        occurred_at = datetime.combine(
            effective_date, class_time, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)
        return EffectiveOccurrence(
            original_date=original_date,
            original_time=original_time,
            effective_date=effective_date,
            occurred_at=occurred_at,
            class_time=class_time,
            duration_minutes=duration_minutes,
            instructor_id=instructor_id,
            is_rescheduled=is_rescheduled,
            is_cancelled=is_cancelled,
            cancelling_range_id=cancelling_range_id,
        )

    # -- weekday lookups (mirror the seed) -------------------------------

    @staticmethod
    def _day_short(when: date) -> str:
        """Map a date to its short weekday name (sun..sat), like the seed."""
        return _DAY_SHORT[(when.weekday() + 1) % 7]

    def _day_flag(self, gym_class: ExpanderClass, when: date) -> bool:
        """Whether the class's flag for ``when``'s weekday is set."""
        return bool(getattr(gym_class, self._day_short(when)))

    def instructor_for(
        self,
        gym_class: ExpanderClass,
        when: date,
    ) -> UUID | None:
        """The class's default instructor for ``when``'s weekday slot.

        Public (not just an internal recurrence-resolution step): the class
        edit paths (``ClassesUndoService.resolve_default_instructor``) reuse
        this directly to compute the weekday-default fallback for an override
        upsert / reschedule that omits an instructor override, so that
        fallback can never drift from the expander's own weekday-default
        semantics (see ``_resolve_instance``).
        """
        return getattr(
            gym_class, f"{self._day_short(when)}{_INSTRUCTOR_SUFFIX}"
        )
