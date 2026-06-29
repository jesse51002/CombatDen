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
from datetime import time
from uuid import UUID

from schema.video import GymVideoSpecSource
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.presets import SQL_DIR
from src.presets.schema.presets_schema import PresetImportResponse
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

# ── Synthesised schedule defaults ────────────────────────────────────────────
# These values are applied to every imported class because the template does
# not carry a time-of-day or duration — the owner edits them after import.
# class_time MUST be a datetime.time (not a "HH:MM" string): the SQL binds it to
# a Postgres TIME parameter, and asyncpg's TIME codec requires a time object.
_DEFAULT_CLASS_TIME = time(9, 0)
_DEFAULT_DURATION_MINUTES = 60
_DEFAULT_POINTS_WORTH = 50

# Demo: how many of the imported videos to re-mark as 'manual' so the gym's
# "Your videos" section isn't empty right after an import.
_MANUAL_SEED_COUNT = 3

# Fallback last-name when an instructor is listed under a single word only.
_FALLBACK_LAST_NAME = "Coach"


class PresetsService:
    """Transactionally imports a video_gym template into a real gym's tables."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

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

            # ── Classes + instructors (soft-delete then insert) ───────────
            await session.execute(
                text(soft_delete_classes_sql), {"gym_id": gym_id_str}
            )
            trainer_cache: dict[tuple[str, str], str] = {}
            classes = (
                self._as_list(row["classes"]) if row["has_classes"] else []
            )
            for c in classes:
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
                await session.execute(
                    text(insert_class_sql),
                    {
                        "gym_id": gym_id_str,
                        "class_name": c["name"],
                        "class_description": c["description"],
                        "image_url": c["image_url"],
                        "points_worth": _DEFAULT_POINTS_WORTH,
                        "class_time": _DEFAULT_CLASS_TIME,
                        "duration_minutes": _DEFAULT_DURATION_MINUTES,
                        "instructor_id": emp_id,
                    },
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
