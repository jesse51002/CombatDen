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

from src.classes.schema.classes_expander_schema import ExpanderClass
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

# Past-history seeding: how far back to materialize class_history + attendance so
# a freshly-imported gym shows realistic attendance counts. Occurrences are
# expanded over [today - _PAST_HISTORY_DAYS, today] and only the past ones kept.
_PAST_HISTORY_DAYS = 30
# Attendance spread per occurrence: draw a random subset (0..MAX_FRACTION) of the
# eligible attendee pool, plus an explicit empty chance, so the seeded history is
# a realistic mix of busy, lightly-attended, and empty occurrences.
_ATTENDANCE_MAX_FRACTION = 0.6
_EMPTY_OCCURRENCE_CHANCE = 0.15

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
        soft_delete_classes_sql = load_sql(
            SQL_DIR / "presets_soft_delete_classes.sql"
        )
        delete_attendance_sql = load_sql(
            SQL_DIR / "presets_delete_attendance.sql"
        )
        delete_class_history_sql = load_sql(
            SQL_DIR / "presets_delete_class_history.sql"
        )
        insert_class_sql = load_sql(SQL_DIR / "presets_insert_class.sql")
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

            # ── Classes + instructors (reset, insert, then seed history) ──
            # Reset: soft-delete prior classes and hard-wipe this gym's seeded
            # class_history + attendance (FK order: attendance before history)
            # so a re-import (demo reset) regenerates a clean past month instead
            # of piling up duplicate occurrences.
            await session.execute(
                text(soft_delete_classes_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_attendance_sql), {"gym_id": gym_id_str}
            )
            await session.execute(
                text(delete_class_history_sql), {"gym_id": gym_id_str}
            )
            trainer_cache: dict[tuple[str, str], str] = {}
            classes = (
                self._as_list(row["classes"]) if row["has_classes"] else []
            )
            expander_classes: list[ExpanderClass] = []
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
                            "class_time": class_time,
                            "duration_minutes": _DEFAULT_DURATION_MINUTES,
                            "instructor_id": emp_id,
                        },
                    )
                ).mappings().fetchone()
                expander_classes.append(
                    self._to_expander_class(
                        class_id=inserted["class_id"],
                        gym_id=gym_id,
                        class_time=class_time,
                        instructor_id=emp_id,
                        start_date=inserted["start_date"],
                    )
                )

            # Seed the past month of class_history + attendance for these
            # classes so the imported gym shows realistic attendance counts.
            await self._seed_history_and_attendance(
                session, gym_id_str, expander_classes
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

    # ── Class history + attendance seeding ─────────────────────────────────────

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
        expander_classes: list[ExpanderClass],
    ) -> None:
        """Materialize the past month of class_history + attendance.

        For each imported class, expand its occurrences over
        ``[today - _PAST_HISTORY_DAYS, today]`` via the canonical expander, keep
        only the ones that have already occurred, write a ``class_history`` row
        per occurrence, and attribute a random subset of the gym's eligible
        members to it. Eligibility is date-independent for this demo seed: any
        member holding a synced membership can attend any past occurrence,
        attributed to one of their memberships (NOT-NULL plan_id/item_id) — so
        attendance spreads evenly across the whole month instead of bunching on
        the dates that members' memberships happen to span. A no-op when the
        import wrote no classes.
        """
        if not expander_classes:
            return

        gym_tz = (
            await session.execute(
                text(load_sql(SQL_DIR / "presets_load_gym_timezone.sql")),
                {"gym_id": gym_id_str},
            )
        ).scalar_one()
        membership_rows = (
            await session.execute(
                text(load_sql(SQL_DIR / "presets_load_gym_memberships.sql")),
                {"gym_id": gym_id_str},
            )
        ).mappings().all()

        today = date.today()
        window_start = today - timedelta(days=_PAST_HISTORY_DAYS)
        now = datetime.now(UTC)
        pool = self._eligible_attendees(membership_rows)

        insert_history_sql = load_sql(
            SQL_DIR / "presets_insert_class_history.sql"
        )
        insert_attendance_sql = load_sql(
            SQL_DIR / "presets_insert_attendance.sql"
        )
        for gym_class in expander_classes:
            await self._seed_one_class(
                session=session,
                gym_id_str=gym_id_str,
                gym_class=gym_class,
                gym_tz=gym_tz,
                window_start=window_start,
                window_end=today,
                now=now,
                pool=pool,
                insert_history_sql=insert_history_sql,
                insert_attendance_sql=insert_attendance_sql,
            )

    async def _seed_one_class(
        self,
        session: AsyncSession,
        gym_id_str: str,
        gym_class: ExpanderClass,
        gym_tz: str,
        window_start: date,
        window_end: date,
        now: datetime,
        pool: _AttendeePool,
        insert_history_sql: str,
        insert_attendance_sql: str,
    ) -> None:
        """Write class_history + attendance for one class's past occurrences."""
        occurrences = self._expander.expand(
            gym_class, [], [], window_start, window_end, gym_tz
        )
        for occ in occurrences:
            if occ.occurred_at >= now:
                continue  # hasn't happened yet — history is past-only
            class_history_id = (
                await session.execute(
                    text(insert_history_sql),
                    {
                        "class_id": str(gym_class.class_id),
                        "gym_id": gym_id_str,
                        "instructor_id": (
                            str(occ.instructor_id)
                            if occ.instructor_id is not None
                            else None
                        ),
                        "occurred_at": occ.occurred_at,
                        "duration_minutes": occ.duration_minutes,
                    },
                )
            ).scalar_one()
            await self._seed_attendance(
                session=session,
                gym_id_str=gym_id_str,
                class_history_id=class_history_id,
                pool=pool,
                insert_attendance_sql=insert_attendance_sql,
            )

    async def _seed_attendance(
        self,
        session: AsyncSession,
        gym_id_str: str,
        class_history_id: UUID,
        pool: _AttendeePool,
        insert_attendance_sql: str,
    ) -> None:
        """Attribute a random subset of the eligible pool to one occurrence.

        The pool is date-independent (every member with a synced membership), so
        attendance spreads evenly across the month. A fraction
        (0..``_ATTENDANCE_MAX_FRACTION``) of the pool attends, with an explicit
        empty chance, so the seeded history is a busy / light / empty mix.
        Distinct members per occurrence satisfy UNIQUE(member_id,
        class_history_id); each row is attributed to that member's pinned
        membership (plan_id + item_id).
        """
        if not pool or random.random() < _EMPTY_OCCURRENCE_CHANCE:
            return
        n = random.randint(0, int(len(pool) * _ATTENDANCE_MAX_FRACTION))
        if n == 0:
            return
        rows = [
            {
                "member_id": str(member_id),
                "gym_id": gym_id_str,
                "class_history_id": str(class_history_id),
                "plan_id": str(plan_id),
                "item_id": str(item_id),
            }
            for member_id, plan_id, item_id in random.sample(pool, n)
        ]
        await session.execute(text(insert_attendance_sql), rows)

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
