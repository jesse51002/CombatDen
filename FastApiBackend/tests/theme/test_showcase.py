"""Integration tests for ThemeShowcaseService against the shared local DB.

Regression guard for the class-system rebuild: the showcase classes SQL
resolves each class's display instructor from the CURRENT schedule
version's ``weekday_slots`` JSONB (``gym_class_schedules_current``) —
first non-null ``instructor_id`` in day order ('all', mon..sun), then
slot order — never from the retired per-day columns on ``gym_classes``.

Service-level (no live backend needed): rows are inserted directly and
deleted in ``finally`` — exactly what each test creates, nothing else.
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.theme.service.theme_showcase_service import ThemeShowcaseService
from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = UUID(SEEDED_GYM_ID)

_INSERT_CLASS = text(
    "INSERT INTO gym_classes (class_id, gym_id, class_name,"
    " class_description, image_url, points_worth, is_active, is_deleted)"
    " VALUES (:class_id, :gym_id, :class_name, :description,"
    " :image_url, 50, TRUE, FALSE)"
)
_INSERT_SCHEDULE = text(
    "INSERT INTO gym_class_schedules (schedule_id, class_id, gym_id,"
    " effective_from, timezone, duration_minutes, recurring_unit,"
    " recurring_interval, weekday_slots, start_date)"
    " VALUES (:schedule_id, :class_id, :gym_id, :effective_from, 'UTC',"
    " 60, 'weekly', 1, CAST(:weekday_slots AS JSONB), :start_date)"
)
_INSERT_TRAINER = text(
    "INSERT INTO gym_employees (employee_id, gym_id, employee_type,"
    " first_name, last_name, employee_pic_url,"
    " employee_public_description)"
    " VALUES (:employee_id, :gym_id, 'trainer', :first_name, :last_name,"
    " :pic_url, :bio)"
)
_INSERT_REWARD = text(
    "INSERT INTO gym_rewards (reward_id, gym_id, title, image_url,"
    " price_label, point_cost, is_active)"
    " VALUES (:reward_id, :gym_id, :title, :image_url, :price_label,"
    " :point_cost, TRUE)"
)
_DELETE_SCHEDULES = text(
    "DELETE FROM gym_class_schedules WHERE class_id = :class_id"
)
_DELETE_CLASS = text("DELETE FROM gym_classes WHERE class_id = :class_id")
_DELETE_EMPLOYEE = text(
    "DELETE FROM gym_employees WHERE employee_id = :employee_id"
)
_DELETE_REWARD = text(
    "DELETE FROM gym_rewards WHERE reward_id = :reward_id"
)


class _ShowcaseFixture:
    """Insert/delete exactly the rows one showcase test needs."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool
        self.class_ids: list[UUID] = []
        self.employee_ids: list[UUID] = []
        self.reward_ids: list[UUID] = []

    async def add_trainer(
        self, *, first_name: str, last_name: str, bio: str, pic_url: str
    ) -> UUID:
        employee_id = uuid4()
        async with self._db.session() as session:
            await session.execute(
                _INSERT_TRAINER,
                {
                    "employee_id": str(employee_id),
                    "gym_id": str(GYM_ID),
                    "first_name": first_name,
                    "last_name": last_name,
                    "pic_url": pic_url,
                    "bio": bio,
                },
            )
            await session.commit()
        self.employee_ids.append(employee_id)
        return employee_id

    async def add_class(
        self,
        *,
        class_name: str,
        description: str,
        image_url: str,
        versions: list[dict],
    ) -> UUID:
        """A class identity plus its schedule ``versions`` (each a dict
        with ``effective_from`` + ``weekday_slots``), oldest first."""
        class_id = uuid4()
        async with self._db.session() as session:
            await session.execute(
                _INSERT_CLASS,
                {
                    "class_id": str(class_id),
                    "gym_id": str(GYM_ID),
                    "class_name": class_name,
                    "description": description,
                    "image_url": image_url,
                },
            )
            for version in versions:
                await session.execute(
                    _INSERT_SCHEDULE,
                    {
                        "schedule_id": str(uuid4()),
                        "class_id": str(class_id),
                        "gym_id": str(GYM_ID),
                        "effective_from": version["effective_from"],
                        "weekday_slots": json.dumps(
                            version["weekday_slots"]
                        ),
                        "start_date": date(2020, 1, 1),
                    },
                )
            await session.commit()
        self.class_ids.append(class_id)
        return class_id

    async def add_reward(
        self,
        *,
        title: str,
        image_url: str,
        price_label: str,
        point_cost: int,
    ) -> UUID:
        reward_id = uuid4()
        async with self._db.session() as session:
            await session.execute(
                _INSERT_REWARD,
                {
                    "reward_id": str(reward_id),
                    "gym_id": str(GYM_ID),
                    "title": title,
                    "image_url": image_url,
                    "price_label": price_label,
                    "point_cost": point_cost,
                },
            )
            await session.commit()
        self.reward_ids.append(reward_id)
        return reward_id

    async def cleanup(self) -> None:
        async with self._db.session() as session:
            for class_id in self.class_ids:
                await session.execute(
                    _DELETE_SCHEDULES, {"class_id": str(class_id)}
                )
                await session.execute(
                    _DELETE_CLASS, {"class_id": str(class_id)}
                )
            for employee_id in self.employee_ids:
                await session.execute(
                    _DELETE_EMPLOYEE, {"employee_id": str(employee_id)}
                )
            for reward_id in self.reward_ids:
                await session.execute(
                    _DELETE_REWARD, {"reward_id": str(reward_id)}
                )
            await session.commit()


@pytest.fixture
def showcase_rows(db_pool: DirectDatabasePool) -> _ShowcaseFixture:
    return _ShowcaseFixture(db_pool)


def _slot(time_str: str, instructor_id: UUID | None) -> dict:
    return {
        "time": time_str,
        "instructor_id": str(instructor_id) if instructor_id else None,
    }


async def test_showcase_resolves_instructor_from_current_version(
    db_pool: DirectDatabasePool, showcase_rows: _ShowcaseFixture
) -> None:
    """The card's instructor comes from the CURRENT (latest
    ``effective_from``) version, first non-null slot in day order —
    null-instructor slots earlier in the week are skipped."""
    service = ThemeShowcaseService(db_pool)
    class_name = f"ZZ Showcase Test {uuid4().hex[:8]}"
    try:
        old_trainer = await showcase_rows.add_trainer(
            first_name="Old",
            last_name="Version",
            bio="retired bio",
            pic_url="https://cdn.example/old.png",
        )
        current_trainer = await showcase_rows.add_trainer(
            first_name="Cara",
            last_name="Current",
            bio="Current-version trainer",
            pic_url="https://cdn.example/cara.png",
        )
        await showcase_rows.add_class(
            class_name=class_name,
            description="Showcase resolution test class",
            image_url="https://cdn.example/class.png",
            versions=[
                {
                    "effective_from": datetime(
                        2020, 1, 1, tzinfo=UTC
                    ),
                    "weekday_slots": {
                        "mon": [_slot("06:00", old_trainer)]
                    },
                },
                {
                    "effective_from": datetime(
                        2021, 1, 1, tzinfo=UTC
                    ),
                    "weekday_slots": {
                        "mon": [_slot("06:00", None)],
                        "wed": [_slot("18:00", current_trainer)],
                    },
                },
            ],
        )

        cards = await service.load_showcase_classes(GYM_ID)

        card = next(c for c in cards if c.name == class_name)
        assert card.description == "Showcase resolution test class"
        assert card.image_url == "https://cdn.example/class.png"
        assert card.instructor_name == "Cara Current"
        assert card.instructor_bio == "Current-version trainer"
        assert card.instructor_image_url == "https://cdn.example/cara.png"
    finally:
        await showcase_rows.cleanup()


async def test_showcase_card_without_instructor_still_returned(
    db_pool: DirectDatabasePool, showcase_rows: _ShowcaseFixture
) -> None:
    """A class whose slots carry no instructor still gets a card
    (instructor fields null)."""
    service = ThemeShowcaseService(db_pool)
    class_name = f"ZZ Showcase NoInstr {uuid4().hex[:8]}"
    try:
        await showcase_rows.add_class(
            class_name=class_name,
            description="No instructor assigned",
            image_url="https://cdn.example/noinstr.png",
            versions=[
                {
                    "effective_from": datetime(
                        2021, 1, 1, tzinfo=UTC
                    ),
                    "weekday_slots": {"fri": [_slot("07:30", None)]},
                }
            ],
        )

        cards = await service.load_showcase_classes(GYM_ID)

        card = next(c for c in cards if c.name == class_name)
        assert card.instructor_name is None
        assert card.instructor_bio is None
        assert card.instructor_image_url is None
    finally:
        await showcase_rows.cleanup()


async def test_showcase_rewards_returns_created_card(
    db_pool: DirectDatabasePool, showcase_rows: _ShowcaseFixture
) -> None:
    """The rewards read returns the created reward card's fields."""
    service = ThemeShowcaseService(db_pool)
    title = f"ZZ Showcase Reward {uuid4().hex[:8]}"
    try:
        await showcase_rows.add_reward(
            title=title,
            image_url="https://cdn.example/reward.png",
            price_label="Free",
            point_cost=1234,
        )

        cards = await service.load_showcase_rewards(GYM_ID)

        card = next(c for c in cards if c.title == title)
        assert card.image_url == "https://cdn.example/reward.png"
        assert card.price_label == "Free"
        assert card.points_cost == 1234
    finally:
        await showcase_rows.cleanup()
