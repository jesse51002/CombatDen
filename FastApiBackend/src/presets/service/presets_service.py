"""PresetsService — transactional import of a video_gym template into a real gym.

A preset import copies one of the 76 slug-keyed ``video_gym*`` templates into a
real gym's production tables in a single database transaction. It is re-pickable
(calling it again on the same gym overwrites the prior import). No demo logic
lives here — this is a real production write path, simply gated to an email
allowlist in the router for now.

Transaction rollback: the entire import uses one ``async with session.begin()``
block. Any unhandled exception — including a CHECK violation (e.g. a template
reward with ``points_cost = 0`` violating ``gym_rewards.point_cost > 0``) —
causes the session to roll back automatically on context-manager exit. No partial
state is ever committed.
"""

from __future__ import annotations

import json
import random
from collections.abc import Mapping, Sequence
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID

from schema.gym_class import RecurringUnit
from schema.video import GymVideoSpecSource
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.classes.schema.classes_expander_schema import (
    EffectiveOccurrence,
    ExpanderClass,
)
from src.classes.service.classes_expander import ClassesExpander
from src.presets import SQL_DIR
from src.presets.schema.presets_schema import PresetImportResponse
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

# ── Synthesised schedule defaults ────────────────────────────────────────────
# The template carries no time-of-day or duration, so the import synthesises a
# realistic schedule. Class times cycle through _CLASS_TIME_SLOTS by index so an
# imported lineup spreads across the day (early-morning → evening) instead of all
# landing at one hour; duration/points stay fixed defaults the owner edits later.
# Each slot MUST be a datetime.time (not a "HH:MM" string): the SQL binds it to a
# Postgres TIME parameter, and asyncpg's TIME codec requires a time object.
_CLASS_TIME_SLOTS = [
    time(6, 0),
    time(7, 30),
    time(9, 0),
    time(12, 0),
    time(17, 0),
    time(18, 30),
    time(20, 0),
]
_DEFAULT_DURATION_MINUTES = 60
_DEFAULT_POINTS_WORTH = 50

# The schedule shape's recurrence anchor (gym_class_schedules.start_date):
# backdated so the weekly recurrence already covers the seeded past month AND
# the current week. The live board expands from start_date forward, so this
# only means the class "has been running" for a month.
_CLASS_RECURRENCE_BACKDATE_DAYS = 35
# The single imported schedule version's effective_from: backdated well
# before the earliest seeded attendance date (_PAST_HISTORY_DAYS). Purely
# cosmetic -- the FIRST version of a class owns occurrences back to negative
# infinity regardless (ClassesVersionExpander) -- but keeps the stored row
# honest for anyone reading it.
_SCHEDULE_EFFECTIVE_FROM_BACKDATE_DAYS = 40

# Attendance + sign-up seeding: how far back to seed recorded attendance and
# how far ahead to seed upcoming sign-up reservations, so a freshly-imported
# gym shows realistic counts on both past and upcoming classes. Occurrences
# are expanded ONCE over [today - _PAST_HISTORY_DAYS, today +
# _FUTURE_SIGNUP_DAYS], then split by EFFECTIVE START INSTANT (never by date
# — a class later today hasn't started yet): an occurrence whose occurred_at
# is already at/before now gets a member_attendance row (a real check-in
# record, keyed by its original slot) + a mirrored mix of class_signups
# reservations; a not-yet-started occurrence gets ONLY a class_signups
# reservation. member_attendance is never written for a not-yet-started
# occurrence — a sign-up is a reservation, not a check-in, mirroring the live
# sign-up path (``SignupService`` deliberately doesn't record attendance
# early; see its module docstring).
_PAST_HISTORY_DAYS = 30
_FUTURE_SIGNUP_DAYS = 7
# Attendance spread per occurrence: draw a random subset (0..MAX_FRACTION) of the
# eligible attendee pool, plus an explicit empty chance, so the seeded history is
# a realistic mix of busy, lightly-attended, and empty occurrences.
_ATTENDANCE_MAX_FRACTION = 0.6
_EMPTY_OCCURRENCE_CHANCE = 0.15
# Sign-up mix, mirroring Database/python_data/generators/classes.py's
# _past_signups / _future_signups: for a past occurrence, most attendance-less
# occurrences stay sign-up-less too; among attended members, a fraction also
# get a mirrored sign-up (signed-up-and-attended, the rest stay walk-ins); a
# few non-attended members may get a sign-up-only row (no-shows), capped by
# whatever room remains under the occurrence's effective capacity.
_SKIP_SIGNUPS_WHEN_NO_ATTENDANCE_CHANCE = 0.7
_SIGNED_AND_ATTENDED_CHANCE = 0.65
_NO_SHOW_CHANCE = 0.5
_MAX_NO_SHOWS = 3
# When a class has no capacity limit (max_capacity IS NULL — true for every
# preset-imported class today, since the import never sets one), cap the
# no-show / future sign-up draw pool at this many rather than an unbounded
# room.
_UNLIMITED_CAPACITY_SIGNUP_ROOM = 3
_UNLIMITED_CAPACITY_FUTURE_POOL_CAP = 8

# Demo: how many of the imported videos to re-mark as 'manual' so the gym's
# "Your videos" section isn't empty right after an import.
_MANUAL_SEED_COUNT = 3

# Fallback last-name when an instructor is listed under a single word only.
_FALLBACK_LAST_NAME = "Coach"

# The eligible attendee pool for past-occurrence seeding: one (member_id,
# plan_id, item_id) tuple per member who holds any synced membership. The
# membership pins the NOT-NULL attendance attribution; it need NOT span the
# occurrence date (demo check-ins are attributed loosely).
_AttendeePool = list[tuple[UUID, UUID, UUID]]


class PresetsService:
    """Transactionally imports a video_gym template into a real gym's tables."""

    def __init__(
        self, db_pool: DirectDatabasePool, expander: ClassesExpander
    ) -> None:
        self._db = db_pool
        # The canonical recurrence expander (pure, stateless) — reused to
        # materialize each imported class's past occurrences exactly as the live
        # board / check-in paths would, so seeded history can never disagree.
        self._expander = expander

    # ── Public API ────────────────────────────────────────────────────────────

    async def import_template(
        self, gym_id: UUID, video_gym_id: str
    ) -> PresetImportResponse:
        """Copy one template's content into the gym's production tables.

        All writes execute in a single transaction that rolls back automatically
        on any error (including DB-level CHECK violations). The import is
        re-pickable: calling it again on the same gym replaces the prior import.

        Args:
            gym_id: The target real gym (UUID-keyed production tables).
            video_gym_id: The slug of the ``video_gym`` template to import from.

        Returns:
            A :class:`PresetImportResponse` with counts of what was written.

        Raises:
            ValueError: When the template slug does not exist.
            Exception: Any DB error propagates; the caller maps it to HTTP.
        """
        load_template_sql = load_sql(SQL_DIR / "presets_load_template.sql")
        insert_spec_version_sql = load_sql(
            SQL_DIR / "presets_insert_spec_version.sql"
        )
        set_theme_sql = load_sql(SQL_DIR / "presets_set_theme.sql")
        insert_run_sql = load_sql(SQL_DIR / "presets_insert_run.sql")
        insert_feed_sql = load_sql(SQL_DIR / "presets_insert_feed.sql")
        insert_rejected_feed_sql = load_sql(
            SQL_DIR / "presets_insert_rejected_feed.sql"
        )
        seed_manual_sql = load_sql(SQL_DIR / "presets_seed_manual_videos.sql")
        count_owner_sql = load_sql(SQL_DIR / "presets_count_owner_feed.sql")
        delete_class_signups_sql = load_sql(
            SQL_DIR / "presets_delete_class_signups.sql"
        )
        delete_attendance_sql = load_sql(
            SQL_DIR / "presets_delete_attendance.sql"
        )
        delete_instance_exceptions_sql = load_sql(
            SQL_DIR / "presets_delete_instance_exceptions.sql"
        )
        delete_range_exceptions_sql = load_sql(
            SQL_DIR / "presets_delete_range_exceptions.sql"
        )
        delete_class_schedules_sql = load_sql(
            SQL_DIR / "presets_delete_class_schedules.sql"
        )
        delete_classes_sql = load_sql(SQL_DIR / "presets_delete_classes.sql")
        insert_class_sql = load_sql(SQL_DIR / "presets_insert_class.sql")
        insert_class_schedule_sql = load_sql(
            SQL_DIR / "presets_insert_class_schedule.sql"
        )
        load_gym_timezone_sql = load_sql(
            SQL_DIR / "presets_load_gym_timezone.sql"
        )
        deactivate_rewards_sql = load_sql(
            SQL_DIR / "presets_deactivate_rewards.sql"
        )
        insert_reward_sql = load_sql(SQL_DIR / "presets_insert_reward.sql")

        gym_id_str = str(gym_id)

        async with self._db.session() as session, session.begin():
            row = (
                await session.execute(
                    text(load_template_sql), {"gym_id": video_gym_id}
                )
            ).mappings().fetchone()

            if row is None:
                raise ValueError(f"no template {video_gym_id!r}")

            # ── Spec (append a new versioned row) ────────────────────────
            await session.execute(
                text(insert_spec_version_sql),
                {
                    "gym_id": gym_id_str,
                    "gym_type": json.dumps(self._as_list(row["gym_type"])),
                    "short_videos_desc": row["short_videos_desc"],
                    "short_avoid_desc": row["short_avoid_desc"],
                    "videos_desc": row["videos_desc"],
                    "avoid_desc": row["avoid_desc"],
                    "queries": json.dumps(self._as_list(row["queries"])),
                    "source": GymVideoSpecSource.system_update.value,
                    "imported_from": video_gym_id,
                },
            )

            # ── Theme ─────────────────────────────────────────────────────
            await session.execute(
                text(set_theme_sql),
                {"gym_id": gym_id_str, "theme_design_id": row["theme"]},
            )

            # ── Feed (open a new run; only ids present in the shared pool) ─
            # A new run becomes the gym's latest (served) feed; old runs are
            # retained as history. The owner "Your videos" section is NOT
            # touched (run-independent, persists across re-imports).
            good_ids = self._as_list(row["good_video_ids"])
            if good_ids:
                run_id = (
                    await session.execute(
                        text(insert_run_sql), {"gym_id": gym_id_str}
                    )
                ).scalar_one()
                feed_result = await session.execute(
                    text(insert_feed_sql),
                    {
                        "gym_id": gym_id_str,
                        "run_id": str(run_id),
                        "ids": good_ids,
                    },
                )
                videos_imported = feed_result.rowcount
                # Demo: seed the owner section with a few videos so "Your
                # videos" isn't empty — only on the first import (when it's
                # still empty), so re-imports don't pile up.
                owner_count = (
                    await session.execute(
                        text(count_owner_sql), {"gym_id": gym_id_str}
                    )
                ).scalar_one()
                if owner_count == 0:
                    seed_ids = random.sample(
                        good_ids, min(_MANUAL_SEED_COUNT, len(good_ids))
                    )
                    await session.execute(
                        text(seed_manual_sql),
                        {"gym_id": gym_id_str, "ids": seed_ids},
                    )
                # Seed the template's full automatic-reject list so the gym's
                # rejected view mirrors the scan's complete keep/drop verdict.
                rejected_ids = self._as_list(row["rejected_video_ids"])
                if rejected_ids:
                    await session.execute(
                        text(insert_rejected_feed_sql),
                        {
                            "gym_id": gym_id_str,
                            "run_id": str(run_id),
                            "ids": rejected_ids,
                        },
                    )
            else:
                videos_imported = 0

            # ── Classes + instructors (reset, insert, then seed attendance) ─
            # Reset: hard-delete this gym's prior imported classes + ALL
            # dependents (sign-ups, attendance, exceptions, schedule versions)
            # in FK-safe order, so a re-import (demo reset) always starts from
            # a completely clean slate — ghost past occurrences after a
            # re-import are unacceptable for demo data.
            await session.execute(
                text(delete_class_signups_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_attendance_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_instance_exceptions_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_range_exceptions_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_class_schedules_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_classes_sql), {"gym_id": gym_id_str}
            )

            trainer_cache: dict[tuple[str, str], str] = {}
            classes = (
                self._as_list(row["classes"]) if row["has_classes"] else []
            )
            expander_classes: list[ExpanderClass] = []
            # The class's effective max_capacity (always NULL today — see
            # presets_insert_class.sql — but read from the row rather than
            # assumed, so the sign-up capacity respect below stays correct if
            # a capacity is ever set here).
            class_capacities: dict[UUID, int | None] = {}
            gym_tz = (
                await session.execute(
                    text(load_gym_timezone_sql), {"gym_id": gym_id_str}
                )
            ).scalar_one()
            # One shared mint instant + recurrence anchor for every class in
            # this import (see the constants' docstrings) — the per-class
            # (class_id, effective_from) uniqueness never collides across
            # distinct classes, so sharing one "now" is safe and simpler.
            recurrence_start_date = date.today() - timedelta(
                days=_CLASS_RECURRENCE_BACKDATE_DAYS
            )
            schedule_effective_from = datetime.now(UTC) - timedelta(
                days=_SCHEDULE_EFFECTIVE_FROM_BACKDATE_DAYS
            )
            for i, c in enumerate(classes):
                first, last = self._split_name(c["instructor_name"])
                emp_id = await self._resolve_trainer(
                    session=session,
                    gym_id=gym_id_str,
                    first_name=first,
                    last_name=last,
                    pic_url=c["instructor_image_url"],
                    bio=c["instructor_bio"],
                    cache=trainer_cache,
                )
                # Spread class start times across the day by index.
                class_time = _CLASS_TIME_SLOTS[i % len(_CLASS_TIME_SLOTS)]
                inserted = (
                    await session.execute(
                        text(insert_class_sql),
                        {
                            "gym_id": gym_id_str,
                            "class_name": c["name"],
                            "class_description": c["description"],
                            "image_url": c["image_url"],
                            "points_worth": _DEFAULT_POINTS_WORTH,
                        },
                    )
                ).mappings().fetchone()
                class_id: UUID = inserted["class_id"]
                await session.execute(
                    text(insert_class_schedule_sql),
                    {
                        "class_id": str(class_id),
                        "gym_id": gym_id_str,
                        "effective_from": schedule_effective_from,
                        "timezone": gym_tz,
                        "class_time": class_time,
                        "duration_minutes": _DEFAULT_DURATION_MINUTES,
                        "instructor_id": emp_id,
                        "start_date": recurrence_start_date,
                    },
                )
                expander_classes.append(
                    self._to_expander_class(
                        class_id=class_id,
                        gym_id=gym_id,
                        class_time=class_time,
                        instructor_id=emp_id,
                        start_date=recurrence_start_date,
                    )
                )
                class_capacities[class_id] = inserted["max_capacity"]

            # Seed the past month of member_attendance (real check-in records,
            # keyed by original slot) plus a mirrored mix of class_signups
            # reservations, and the upcoming week of class_signups-only
            # reservations, for these classes so the imported gym shows
            # realistic counts on both past and upcoming occurrences.
            await self._seed_history_and_attendance(
                session, gym_id_str, gym_tz, expander_classes, class_capacities
            )

            # ── Rewards (deactivate then insert) ──────────────────────────
            await session.execute(
                text(deactivate_rewards_sql), {"gym_id": gym_id_str}
            )
            rewards = (
                self._as_list(row["rewards"]) if row["has_rewards"] else []
            )
            for r in rewards:
                await session.execute(
                    text(insert_reward_sql),
                    {
                        "gym_id": gym_id_str,
                        "title": r["title"],
                        "image_url": r["image_url"],
                        "price_label": r["price_label"],
                        "point_cost": r["points_cost"],
                    },
                )

        return PresetImportResponse(
            gym_id=gym_id,
            video_gym_id=video_gym_id,
            videos_imported=videos_imported,
            classes_imported=len(classes),
            rewards_imported=len(rewards),
            theme_design_id=row["theme"],
        )

    # ── Attendance + sign-up seeding ─────────────────────────────────────────

    def _to_expander_class(
        self,
        class_id: UUID,
        gym_id: UUID,
        class_time: time,
        instructor_id: str,
        start_date: date,
    ) -> ExpanderClass:
        """Project a just-inserted preset class onto the expander contract.

        Preset classes are always weekly Mon–Fri (the insert SQL hard-codes the
        flags) with one instructor across every weekday and no end date, so the
        expander reproduces exactly the occurrences the live board would show.
        """
        return ExpanderClass(
            class_id=class_id,
            gym_id=gym_id,
            class_time=class_time,
            duration_minutes=_DEFAULT_DURATION_MINUTES,
            recurring_unit=RecurringUnit.weekly,
            recurring_interval=1,
            mon=True,
            tue=True,
            wed=True,
            thu=True,
            fri=True,
            sat=False,
            sun=False,
            mon_instructor_id=instructor_id,
            tue_instructor_id=instructor_id,
            wed_instructor_id=instructor_id,
            thu_instructor_id=instructor_id,
            fri_instructor_id=instructor_id,
            start_date=start_date,
            end_date=None,
        )

    async def _seed_history_and_attendance(
        self,
        session: AsyncSession,
        gym_id_str: str,
        gym_tz: str,
        expander_classes: list[ExpanderClass],
        class_capacities: dict[UUID, int | None],
    ) -> None:
        """Seed the past month of attendance + upcoming sign-up reservations.

        For each imported class, expand its occurrences ONCE over
        ``[today - _PAST_HISTORY_DAYS, today + _FUTURE_SIGNUP_DAYS]`` via the
        canonical expander (the same call the rest of the preset already uses —
        no separate re-derivation for the future side), then split by EFFECTIVE
        START INSTANT (never by date — a class later TODAY hasn't happened yet
        and must not be seeded as attended): an occurrence whose
        ``occurred_at`` is already at/before now gets a random subset of the
        gym's eligible members as a recorded ``member_attendance`` row (keyed
        by its original slot) + a mirrored mix of ``class_signups``
        reservations; a not-yet-started occurrence gets ONLY a
        ``class_signups`` reservation (no attendance — a sign-up is a
        reservation, not a check-in). Eligibility is date-independent for this
        demo seed: any member holding a synced membership can attend / sign up
        for any occurrence, attributed to one of their memberships (NOT-NULL
        plan_id/item_id) — so participation spreads evenly across the window
        instead of bunching on the dates that members' memberships happen to
        span. A no-op when the import wrote no classes.
        """
        if not expander_classes:
            return

        membership_rows = (
            await session.execute(
                text(load_sql(SQL_DIR / "presets_load_gym_memberships.sql")),
                {"gym_id": gym_id_str},
            )
        ).mappings().all()

        today = date.today()
        window_start = today - timedelta(days=_PAST_HISTORY_DAYS)
        window_end = today + timedelta(days=_FUTURE_SIGNUP_DAYS)
        now = datetime.now(UTC)
        pool = self._eligible_attendees(membership_rows)

        insert_attendance_sql = load_sql(
            SQL_DIR / "presets_insert_attendance.sql"
        )
        insert_signup_sql = load_sql(
            SQL_DIR / "presets_insert_class_signup.sql"
        )
        for gym_class in expander_classes:
            await self._seed_one_class(
                session=session,
                gym_id_str=gym_id_str,
                gym_class=gym_class,
                max_capacity=class_capacities.get(gym_class.class_id),
                gym_tz=gym_tz,
                now=now,
                window_start=window_start,
                window_end=window_end,
                pool=pool,
                insert_attendance_sql=insert_attendance_sql,
                insert_signup_sql=insert_signup_sql,
            )

    async def _seed_one_class(
        self,
        session: AsyncSession,
        gym_id_str: str,
        gym_class: ExpanderClass,
        max_capacity: int | None,
        gym_tz: str,
        now: datetime,
        window_start: date,
        window_end: date,
        pool: _AttendeePool,
        insert_attendance_sql: str,
        insert_signup_sql: str,
    ) -> None:
        """Write attendance + sign-ups for every occurrence of one class.

        An occurrence whose EFFECTIVE START INSTANT has already passed
        (``occ.occurred_at <= now`` — INSTANT-based, never day-based: a class
        later TODAY hasn't started yet) gets a random subset of attendance (a
        real check-in record) and a mirrored mix of sign-up reservations. A
        not-yet-started occurrence gets ONLY a sign-up reservation — no
        ``member_attendance`` — mirroring the live sign-up path, which
        deliberately never records attendance for a not-yet-started occurrence
        (see ``SignupService``'s module docstring). This import never writes
        exceptions, so every occurrence's ``original_time`` equals the class's
        schedule ``class_time`` and ``effective_date`` equals ``original_date``.
        """
        occurrences = self._expander.expand(
            gym_class, [], [], window_start, window_end, gym_tz
        )
        for occ in occurrences:
            if occ.occurred_at <= now:
                await self._seed_past_occurrence(
                    session=session,
                    gym_id_str=gym_id_str,
                    gym_class=gym_class,
                    occ=occ,
                    max_capacity=max_capacity,
                    pool=pool,
                    insert_attendance_sql=insert_attendance_sql,
                    insert_signup_sql=insert_signup_sql,
                )
            else:
                await self._seed_future_signups(
                    session=session,
                    gym_id_str=gym_id_str,
                    class_id=gym_class.class_id,
                    original_date=occ.original_date,
                    original_time=occ.original_time,
                    max_capacity=max_capacity,
                    pool=pool,
                    insert_signup_sql=insert_signup_sql,
                )

    async def _seed_past_occurrence(
        self,
        session: AsyncSession,
        gym_id_str: str,
        gym_class: ExpanderClass,
        occ: EffectiveOccurrence,
        max_capacity: int | None,
        pool: _AttendeePool,
        insert_attendance_sql: str,
        insert_signup_sql: str,
    ) -> None:
        """Write one already-occurred occurrence's attendance + sign-ups."""
        attended_ids = await self._seed_attendance(
            session=session,
            gym_id_str=gym_id_str,
            class_id=gym_class.class_id,
            occ=occ,
            pool=pool,
            insert_attendance_sql=insert_attendance_sql,
        )
        await self._seed_past_signups(
            session=session,
            gym_id_str=gym_id_str,
            class_id=gym_class.class_id,
            original_date=occ.original_date,
            original_time=occ.original_time,
            attended_ids=attended_ids,
            max_capacity=max_capacity,
            pool=pool,
            insert_signup_sql=insert_signup_sql,
        )

    async def _seed_attendance(
        self,
        session: AsyncSession,
        gym_id_str: str,
        class_id: UUID,
        occ: EffectiveOccurrence,
        pool: _AttendeePool,
        insert_attendance_sql: str,
    ) -> list[UUID]:
        """Attribute a random subset of the eligible pool to one occurrence.

        The pool is date-independent (every member with a synced membership), so
        attendance spreads evenly across the month. A fraction
        (0..``_ATTENDANCE_MAX_FRACTION``) of the pool attends, with an explicit
        empty chance, so the seeded history is a busy / light / empty mix.
        Distinct members per occurrence satisfy
        ``UNIQUE(member_id, class_id, original_date)``; each row is attributed
        to that member's pinned membership (plan_id + item_id) and keyed by
        the occurrence's original slot (``original_date`` + ``original_time``)
        with ``occurred_at`` as the denormalized effective UTC instant.

        Returns the attended member_ids so the caller can mirror a sign-up
        onto some of them (signed-up-and-attended) without re-deriving who
        attended.
        """
        if not pool or random.random() < _EMPTY_OCCURRENCE_CHANCE:
            return []
        n = random.randint(0, int(len(pool) * _ATTENDANCE_MAX_FRACTION))
        if n == 0:
            return []
        sampled = random.sample(pool, n)
        rows = [
            {
                "member_id": str(member_id),
                "gym_id": gym_id_str,
                "class_id": str(class_id),
                "original_date": occ.original_date,
                "original_time": occ.original_time,
                "occurred_at": occ.occurred_at,
                "plan_id": str(plan_id),
                "item_id": str(item_id),
            }
            for member_id, plan_id, item_id in sampled
        ]
        await session.execute(text(insert_attendance_sql), rows)
        return [member_id for member_id, _, _ in sampled]

    # ── Sign-up (class_signups) seeding ─────────────────────────────────────

    async def _seed_past_signups(
        self,
        session: AsyncSession,
        gym_id_str: str,
        class_id: UUID,
        original_date: date,
        original_time: time,
        attended_ids: list[UUID],
        max_capacity: int | None,
        pool: _AttendeePool,
        insert_signup_sql: str,
    ) -> None:
        """Sign-ups for one already-occurred occurrence: a realistic mix of
        signed-up-and-attended, no-show (signed up, never attended), and
        walk-in (attended, no sign-up row — left alone, so attendance is
        untouched). Mirrors
        ``Database/python_data/generators/classes.py::_past_signups``.

        Respects ``max_capacity`` by never growing the signed-up-or-attended
        count past it: no-show sign-ups only fill whatever room remains after
        the occurrence's (already-written, unbounded) attendance count — when
        attendance alone already fills/exceeds the room, only already-attended
        members get a mirrored sign-up row.
        """
        if (
            not attended_ids
            and random.random() < _SKIP_SIGNUPS_WHEN_NO_ATTENDANCE_CHANCE
        ):
            return  # most attendance-less occurrences stay signup-less too

        signed_and_attended = {
            member_id
            for member_id in attended_ids
            if random.random() < _SIGNED_AND_ATTENDED_CHANCE
        }

        room = (
            _UNLIMITED_CAPACITY_SIGNUP_ROOM
            if max_capacity is None
            else max(max_capacity - len(attended_ids), 0)
        )
        attended_set = set(attended_ids)
        no_show_pool = [
            member_id
            for member_id, _, _ in pool
            if member_id not in attended_set
        ]
        no_shows: set[UUID] = set()
        max_no_shows = min(len(no_show_pool), _MAX_NO_SHOWS, room)
        if max_no_shows > 0 and random.random() < _NO_SHOW_CHANCE:
            no_shows = set(
                random.sample(no_show_pool, random.randint(1, max_no_shows))
            )

        await self._insert_signups(
            session,
            gym_id_str,
            class_id,
            original_date,
            original_time,
            signed_and_attended | no_shows,
            insert_signup_sql,
        )

    async def _seed_future_signups(
        self,
        session: AsyncSession,
        gym_id_str: str,
        class_id: UUID,
        original_date: date,
        original_time: time,
        max_capacity: int | None,
        pool: _AttendeePool,
        insert_signup_sql: str,
    ) -> None:
        """Sign-ups-only for a not-yet-occurred occurrence — no attendance
        exists yet. Mirrors
        ``Database/python_data/generators/classes.py::_future_signups``,
        respecting ``max_capacity`` as the draw pool's cap.
        """
        member_ids = [member_id for member_id, _, _ in pool]
        if not member_ids:
            return
        pool_size = (
            min(len(member_ids), _UNLIMITED_CAPACITY_FUTURE_POOL_CAP)
            if max_capacity is None
            else min(max_capacity, len(member_ids))
        )
        if pool_size == 0:
            return
        k = random.randint(0, pool_size)
        if k == 0:
            return
        await self._insert_signups(
            session,
            gym_id_str,
            class_id,
            original_date,
            original_time,
            set(random.sample(member_ids, k)),
            insert_signup_sql,
        )

    async def _insert_signups(
        self,
        session: AsyncSession,
        gym_id_str: str,
        class_id: UUID,
        original_date: date,
        original_time: time,
        member_ids: set[UUID],
        insert_signup_sql: str,
    ) -> None:
        """Write one class_signups row per member for one occurrence.

        Idempotent (``ON CONFLICT DO NOTHING``); a no-op when ``member_ids``
        is empty.
        """
        if not member_ids:
            return
        rows = [
            {
                "gym_id": gym_id_str,
                "class_id": str(class_id),
                "member_id": str(member_id),
                "original_date": original_date,
                "original_time": original_time,
            }
            for member_id in member_ids
        ]
        await session.execute(text(insert_signup_sql), rows)

    @staticmethod
    def _eligible_attendees(
        membership_rows: Sequence[Mapping],
    ) -> _AttendeePool:
        """One membership per member for date-independent attendance seeding.

        Every member holding any synced membership is eligible for every past
        occurrence (demo check-ins are attributed loosely — the membership need
        not span the occurrence date). When a member holds several, prefer an
        active (no end/cancel) one, then the most recent start — a deterministic
        pick for the NOT-NULL plan_id/item_id attribution. A member with no
        membership at all is absent (the schema's NOT-NULL floor).
        """
        best: dict[UUID, tuple[bool, date, UUID, UUID]] = {}
        for m in membership_rows:
            member_id = m["member_id"]
            ranked = (
                m["end_date"] is None and m["cancel_date"] is None,
                m["start_date"],
                m["plan_id"],
                m["item_id"],
            )
            current = best.get(member_id)
            if current is None or ranked[:2] > current[:2]:
                best[member_id] = ranked
        return [(mid, v[2], v[3]) for mid, v in best.items()]

    # ── Private helpers ───────────────────────────────────────────────────────

    @staticmethod
    def _as_list(value: object) -> list:
        """A JSONB column as a Python list — tolerant of the driver returning
        either a decoded list or the raw JSON string."""
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return value  # already decoded by the driver

    @staticmethod
    def _split_name(full_name: str | None) -> tuple[str, str]:
        """Split a full name into (first, last).

        Splits on the last space so "Mary Jo Smith" → ("Mary Jo", "Smith").
        When there is no space — or the name is absent — the whole string
        becomes ``first_name`` and ``_FALLBACK_LAST_NAME`` is used as
        ``last_name`` so the DB NOT NULL / non-empty CHECK is always satisfied.
        """
        if not full_name or not full_name.strip():
            return ("Instructor", _FALLBACK_LAST_NAME)
        parts = full_name.strip().rsplit(" ", 1)
        if len(parts) == 1:
            return (parts[0], _FALLBACK_LAST_NAME)
        return (parts[0], parts[1])

    async def _resolve_trainer(
        self,
        session: AsyncSession,
        gym_id: str,
        first_name: str,
        last_name: str,
        pic_url: str | None,
        bio: str | None,
        cache: dict[tuple[str, str], str],
    ) -> str:
        """Return the employee_id (as a str) for a trainer on this gym.

        Checks the in-transaction cache first to avoid redundant round-trips
        when the same instructor teaches multiple classes. On a cache miss,
        queries the DB: if found, updates the pic/bio and caches the id; if
        not found, inserts a new trainer row and caches the returned id.

        Trainers are never deleted; this is a pure upsert by (first, last).
        """
        find_sql = load_sql(SQL_DIR / "presets_find_trainer.sql")
        insert_sql = load_sql(SQL_DIR / "presets_insert_trainer.sql")
        update_sql = load_sql(SQL_DIR / "presets_update_trainer.sql")

        cache_key = (first_name, last_name)
        if cache_key in cache:
            return cache[cache_key]

        existing = (
            await session.execute(
                text(find_sql),
                {
                    "gym_id": gym_id,
                    "first_name": first_name,
                    "last_name": last_name,
                },
            )
        ).mappings().fetchone()

        if existing is not None:
            emp_id = str(existing["employee_id"])
            await session.execute(
                text(update_sql),
                {
                    "employee_id": emp_id,
                    "employee_pic_url": pic_url,
                    "employee_public_description": bio,
                },
            )
        else:
            inserted = (
                await session.execute(
                    text(insert_sql),
                    {
                        "gym_id": gym_id,
                        "first_name": first_name,
                        "last_name": last_name,
                        "employee_pic_url": pic_url,
                        "employee_public_description": bio,
                    },
                )
            ).mappings().fetchone()
            emp_id = str(inserted["employee_id"])

        cache[cache_key] = emp_id
        return emp_id
