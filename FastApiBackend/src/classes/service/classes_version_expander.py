"""The versioned recurrence expander — a class's full schedule history.

``ClassesVersionExpander`` turns a class's append-only schedule versions
(``gym_class_schedules`` rows) plus its exceptions, over a date window, into
the effective dated occurrences. It wraps the untouched single-shape
``ClassesExpander`` (still the ONE recurrence + exception engine) and adds the
three version rules:

1. **Ownership windowing.** A version owns the occurrences whose ORIGINAL
   instant (``original_date`` + the version's ``class_time`` in the version's
   own frozen ``timezone``) falls inside ``[effective_from, next version's
   effective_from)``. The last version's window extends to infinity; the
   FIRST version's window extends back to negative infinity (its
   ``effective_from`` is just its mint stamp — a class created with a
   backdated ``start_date`` renders its past from version one). Ownership is
   tested on the ORIGINAL slot, before exceptions: an exception may retime or
   reschedule the occurrence anywhere, but the version owning the original
   slot decides whether it exists.
2. **Cross-version date dedup (no day doubling).** When two versions both
   produce an owned candidate on the same gym-local ``original_date`` (the
   old version's occurrence already started before the mint; the new
   version's slot lands later the same day), the EARLIER version wins and the
   newer version emits nothing that day — a class has at most ONE original
   occurrence per gym-local date (the one-per-day invariant).
3. **Per-version timezone.** Each version expands with its OWN frozen zone,
   so instants and ownership can never re-derive differently later — the
   past always renders identically, no matter what happens to
   ``gyms.timezone``.

Like the inner expander it is PURE: no DB, no I/O, no clock. The mint-time
rules (``effective_from`` = server now, the version-change wipe) live in
``ClassesVersionsService``.
"""

from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

from src.classes.schema.classes_expander_schema import (
    EffectiveOccurrence,
    ExpanderInstanceException,
    ExpanderRangeException,
    ExpanderScheduleVersion,
)
from src.classes.service.classes_expander import ClassesExpander


class ClassesVersionExpander:
    """Expands a class's schedule versions into effective occurrences.

    Stateless apart from the injected single-shape engine: a single shared
    instance is safe to reuse.
    """

    def __init__(self, expander: ClassesExpander) -> None:
        self._expander = expander

    def expand(
        self,
        versions: list[ExpanderScheduleVersion],
        instance_exceptions: list[ExpanderInstanceException],
        range_exceptions: list[ExpanderRangeException],
        window_start: date,
        window_end: date,
        include_cancelled: bool = False,
    ) -> list[EffectiveOccurrence]:
        """Yield the class's effective occurrences within the window.

        Args:
            versions: ALL of the class's schedule versions (any order; sorted
                internally by ``effective_from``). Each expands with its own
                frozen timezone.
            instance_exceptions: Single-date overrides for this class. An
                exception binds to whatever slot the owning version defines
                on its ``original_date``.
            range_exceptions: Date-range overrides for this class.
            window_start: First date of interest (inclusive).
            window_end: Last date of interest (inclusive).
            include_cancelled: Passed through to the inner expander —
                cancelled occurrences are dropped (default) or emitted
                flagged for display.

        Returns:
            Owned, deduped effective occurrences sorted by ``occurred_at``,
            each tagged with its owning ``schedule_id`` and the
            ``original_start_at`` instant the ownership test used. Empty for
            an empty version list or an invalid window.
        """
        if not versions or window_start > window_end:
            return []

        ordered = sorted(versions, key=lambda v: v.effective_from)
        claimed_dates: set[date] = set()
        occurrences: list[EffectiveOccurrence] = []
        for index, version in enumerate(ordered):
            window_from = (
                ordered[index].effective_from if index > 0 else None
            )
            window_until = (
                ordered[index + 1].effective_from
                if index + 1 < len(ordered)
                else None
            )
            occurrences.extend(
                self._owned_occurrences(
                    version,
                    window_from,
                    window_until,
                    claimed_dates,
                    instance_exceptions,
                    range_exceptions,
                    window_start,
                    window_end,
                    include_cancelled,
                )
            )

        occurrences.sort(key=lambda occ: occ.occurred_at)
        return occurrences

    def original_start_at(
        self, version: ExpanderScheduleVersion, original_date: date
    ) -> datetime:
        """The UTC instant of ``original_date``'s slot under ``version``.

        The ownership instant: ``original_date`` + the version's
        ``class_time`` interpreted in the version's own frozen timezone.
        Public because the mint engine (``ClassesVersionsService``) computes
        the same instant when collecting future-keyed rows for the
        version-change wipe — it must never drift from the expander's own
        ownership arithmetic.
        """
        return datetime.combine(
            original_date,
            version.class_time,
            tzinfo=ZoneInfo(version.timezone),
        ).astimezone(UTC)

    # -- per-version expansion -------------------------------------------

    def _owned_occurrences(
        self,
        version: ExpanderScheduleVersion,
        window_from: datetime | None,
        window_until: datetime | None,
        claimed_dates: set[date],
        instance_exceptions: list[ExpanderInstanceException],
        range_exceptions: list[ExpanderRangeException],
        window_start: date,
        window_end: date,
        include_cancelled: bool,
    ) -> list[EffectiveOccurrence]:
        """One version's owned occurrences, claiming dates as it goes.

        ``window_from`` is None for the FIRST version (owns back to negative
        infinity); ``window_until`` is None for the LAST (owns to infinity).
        ``claimed_dates`` is shared across versions in ``effective_from``
        order, so an earlier version's claim suppresses a later version's
        same-date candidate (rule 2 — no day doubling).
        """
        expanded = self._expander.expand(
            version,
            instance_exceptions,
            range_exceptions,
            window_start,
            window_end,
            version.timezone,
            include_cancelled,
        )
        owned: list[EffectiveOccurrence] = []
        for occ in expanded:
            slot_instant = self.original_start_at(
                version, occ.original_date
            )
            if window_from is not None and slot_instant < window_from:
                continue
            if window_until is not None and slot_instant >= window_until:
                continue
            if occ.original_date in claimed_dates:
                continue
            claimed_dates.add(occ.original_date)
            owned.append(
                occ.model_copy(
                    update={
                        "schedule_id": version.schedule_id,
                        "original_start_at": slot_instant,
                    }
                )
            )
        return owned
