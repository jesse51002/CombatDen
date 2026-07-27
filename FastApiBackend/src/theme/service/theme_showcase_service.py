"""ThemeShowcaseService — a real gym's branded class/reward cards.

Loads a gym's active class cards (with resolved instructor) and its active
reward cards for the showcase surface. Uses ``DirectDatabasePool`` +
externalised ``.sql`` files.

This is the concern service behind the ``GET /api/v1/gyms/{gym_id}/showcase``
endpoint.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.theme import SQL_DIR
from src.theme.schema.theme_schema import ShowcaseClassCard, ShowcaseRewardCard


class ThemeShowcaseService:
    """Read-only access to a real gym's branded class and reward cards."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    # ── helpers ──────────────────────────────────────────────────

    @staticmethod
    def _instructor_name(
        first_name: str | None, last_name: str | None
    ) -> str | None:
        """A class instructor's display name from first/last (null-safe). None
        when neither part is present."""
        parts = [p for p in (first_name, last_name) if p]
        return " ".join(parts) if parts else None

    # ── showcase reads ────────────────────────────────────────────

    async def load_showcase_classes(
        self, gym_id: UUID
    ) -> list[ShowcaseClassCard]:
        """A real gym's active class cards (with resolved instructor) for the
        showcase, in class-name order."""
        sql = load_sql(SQL_DIR / "theme_load_showcase_classes.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .all()
            )
        return [
            ShowcaseClassCard(
                name=r["name"],
                image_url=r["image_url"],
                description=r["description"],
                instructor_name=self._instructor_name(
                    r["first_name"], r["last_name"]
                ),
                instructor_bio=r["instructor_bio"],
                instructor_image_url=r["instructor_image_url"],
            )
            for r in rows
        ]

    async def load_showcase_rewards(
        self, gym_id: UUID
    ) -> list[ShowcaseRewardCard]:
        """A real gym's active reward cards for the showcase, in points order."""
        sql = load_sql(SQL_DIR / "theme_load_showcase_rewards.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .all()
            )
        return [ShowcaseRewardCard.model_validate(dict(r)) for r in rows]

    async def load_theme_design_id(self, gym_id: UUID) -> str | None:
        """The gym's saved ThemeService design id (None until one is chosen).

        The mobile app re-themes itself to the gym's branding from this id;
        every employee role reads it too. A missing gym yields None (the
        caller's employment/membership at the gym is verified at the router
        layer before this runs)."""
        sql = load_sql(SQL_DIR / "theme_load_gym_design_id.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["theme_design_id"] if row else None
