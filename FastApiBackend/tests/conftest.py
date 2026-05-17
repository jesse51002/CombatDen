"""Root conftest — TestClient + mock auth + mock DB-pool fixtures.

These tests are smoke + edge-case tests that don't require a live
Postgres or Supabase. They use FastAPI's TestClient with the
``Auth`` and DB-pool dependencies overridden to AsyncMock objects so
each test can assert the router wired up the right service method
with the right arguments.
"""

from collections.abc import Generator
from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from src.main import app
from src.shared.auth import Auth


@pytest.fixture
def fake_user_id() -> str:
    """A stable auth user id for the request-scoped fake user."""
    return str(uuid4())


@pytest.fixture
def fake_gym_id() -> str:
    return str(uuid4())


@pytest.fixture
def fake_member_id() -> str:
    return str(uuid4())


@pytest.fixture
def fake_reward_id() -> str:
    return str(uuid4())


@pytest.fixture
def fake_rank_id() -> str:
    return str(uuid4())


@pytest.fixture
def auth_mock(fake_user_id: str) -> AsyncMock:
    """An ``Auth`` double that always succeeds.

    ``get_current_user`` returns a payload whose ``sub`` matches
    ``fake_user_id``. ``verify_*`` methods are no-ops.
    """
    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": fake_user_id,
        "email": "test@example.com",
    }
    auth.verify_gym_employee = AsyncMock(return_value=None)
    auth.verify_can_view_member = AsyncMock(return_value=None)
    return auth


@pytest.fixture
def db_pool_mock() -> MagicMock:
    """A ``DirectDatabasePool`` double whose ``session()`` and
    ``execute_with_retry`` return AsyncMock results.

    Tests configure the AsyncMock return values per-call.
    """
    pool = MagicMock()
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    pool.session.return_value = session
    pool.execute_with_retry = AsyncMock()
    # The lifespan calls ``await pool.engine.dispose()`` on shutdown.
    pool.engine.dispose = AsyncMock()
    return pool


@pytest.fixture
def client(
    auth_mock: MagicMock,
    db_pool_mock: MagicMock,
) -> Generator[TestClient]:
    """A TestClient with auth and db_pool dependencies overridden."""
    container = app.container
    container.auth.override(auth_mock)
    container.db_pool.override(db_pool_mock)
    try:
        with TestClient(app) as c:
            yield c
    finally:
        container.auth.reset_override()
        container.db_pool.reset_override()


@pytest.fixture
def auth_headers() -> dict:
    return {"Authorization": "Bearer fake-jwt"}


def make_member_row(
    *,
    member_id: str,
    gym_id: str,
    user_id: str | None = None,
    first_name: str = "Ada",
    last_name: str = "Lovelace",
    email: str = "ada@example.com",
    points_balance: int = 100,
    last_class: datetime | None = None,
    trial_start_date: date | None = None,
    trial_end_date: date | None = None,
    fully_active_start_date: date | None = None,
    inactive_start_date: date | None = None,
    current_rank_id: str | None = None,
    created_at: datetime | None = None,
) -> dict:
    """A members-row dict shaped to match the SQL RETURNING clauses."""
    return {
        "member_id": member_id,
        "gym_id": gym_id,
        "user_id": user_id,
        "first_name": first_name,
        "last_name": last_name,
        "email": email,
        "points_balance": points_balance,
        "last_class": last_class,
        "trial_start_date": trial_start_date,
        "trial_end_date": trial_end_date,
        "fully_active_start_date": fully_active_start_date,
        "inactive_start_date": inactive_start_date,
        "current_rank_id": current_rank_id,
        "created_at": created_at or datetime.now(UTC),
    }


def make_rank_row(
    *,
    rank_id: str,
    gym_id: str,
    main_rank_num_order: int = 0,
    sub_rank_num_order: int = 0,
    main_name: str = "White",
    sub_name: str = "0 stripes",
    classes_till_rankup: int = 15,
    image_url: str | None = None,
    color: str | None = "#FFFFFF",
    created_at: datetime | None = None,
) -> dict:
    """A gym_ranks-row dict shaped to match SQL RETURNING clauses."""
    return {
        "rank_id": rank_id,
        "gym_id": gym_id,
        "main_rank_num_order": main_rank_num_order,
        "sub_rank_num_order": sub_rank_num_order,
        "main_name": main_name,
        "sub_name": sub_name,
        "classes_till_rankup": classes_till_rankup,
        "image_url": image_url,
        "color": color,
        "created_at": created_at or datetime.now(UTC),
    }


def make_member_list_row(
    *,
    member_id: str,
    first_name: str = "Ada",
    last_name: str = "Lovelace",
    email: str | None = "ada@example.com",
    points_balance: int = 100,
    status: str = "active",
    last_class_days_ago: int | None = 3,
    rank_id: str | None = None,
    main_name: str = "White",
    sub_name: str = "0 stripes",
    color: str | None = "#FFFFFF",
    image_url: str | None = None,
    main_rank_num_order: int = 0,
    sub_rank_num_order: int = 0,
) -> dict:
    """Row shape returned by list_members.sql after the LEFT JOIN."""
    return {
        "member_id": member_id,
        "first_name": first_name,
        "last_name": last_name,
        "email": email,
        "points_balance": points_balance,
        "status": status,
        "last_class_days_ago": last_class_days_ago,
        "rank_rank_id": rank_id,
        "rank_main_name": main_name if rank_id else None,
        "rank_sub_name": sub_name if rank_id else None,
        "rank_color": color if rank_id else None,
        "rank_image_url": image_url if rank_id else None,
        "rank_main_rank_num_order": main_rank_num_order if rank_id else None,
        "rank_sub_rank_num_order": sub_rank_num_order if rank_id else None,
    }


def make_reward_row(
    *,
    reward_id: str,
    gym_id: str,
    title: str = "Free smoothie",
    point_cost: int = 50,
    amount_off: str | None = None,
    image_url: str | None = None,
    is_active: bool = True,
    created_at: datetime | None = None,
) -> dict:
    return {
        "reward_id": reward_id,
        "gym_id": gym_id,
        "title": title,
        "point_cost": point_cost,
        "amount_off": amount_off,
        "image_url": image_url,
        "is_active": is_active,
        "created_at": created_at or datetime.now(UTC),
    }
