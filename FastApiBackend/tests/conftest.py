"""Root conftest — TestClient + mock auth + mock DB-pool fixtures (unit tests)
AND session-scoped integration-test infrastructure (db_pool, stripe_client,
stripe_account_id, gym_id, connect_opts).

Unit tests use the TestClient/AsyncMock fixtures.
Integration / billing tests use the session-scoped Stripe + DB fixtures.
"""

from collections.abc import Generator
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.core.config import settings
from src.main import app
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool
from tests.seed_constants import SEEDED_GYM_ID


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
    auth.verify_gym_owner = AsyncMock(return_value=None)
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
    current_rank_id: str | None = None,
    created_at: datetime | None = None,
    phone: str | None = None,
    address: str | None = None,
    emergency_contact_name: str | None = None,
    emergency_contact_phone: str | None = None,
    emergency_contact_email: str | None = None,
    photo_url: str | None = None,
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
        "current_rank_id": current_rank_id,
        "created_at": created_at or datetime.now(UTC),
        "phone": phone,
        "address": address,
        "emergency_contact_name": emergency_contact_name,
        "emergency_contact_phone": emergency_contact_phone,
        "emergency_contact_email": emergency_contact_email,
        "photo_url": photo_url,
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


# ──────────────────────────────────────────────────────────────────
# Integration-test infrastructure (session-scoped)
# Used by billing / CRM integration tests that talk to a real DB
# and a real Stripe test account. These are no-ops when the env
# variables are absent (tests that need them will error/skip).
# ──────────────────────────────────────────────────────────────────

# Persistent Stripe Custom Connect account for integration tests.
# Created once via script, reused across all test runs (no 50s wait).
# Production uses Express accounts — Custom is only for testing so we
# can programmatically fill onboarding requirements.
# To recreate: poetry run python tests/scripts/create_test_account.py
STRIPE_TEST_ACCOUNT_ID = "acct_1TLWP5LArmKROnJ8"


@pytest.fixture(scope="session")
def db_pool():
    """Session-wide async database pool."""
    pool = DirectDatabasePool()
    yield pool


@pytest.fixture(scope="session")
def stripe_client():
    """Session-wide Stripe client using the test secret key."""
    return PaymentsStripeClient(secret_key=settings.stripe_secret_key)


@pytest.fixture(scope="session")
def stripe_account_id():
    """Return the persistent Stripe Custom Connect account ID."""
    return STRIPE_TEST_ACCOUNT_ID


@pytest.fixture(scope="session")
def connect_opts(stripe_client, stripe_account_id):
    """Stripe Connect request options for the test account."""
    return PaymentsStripeClient.connect_opts_readonly(stripe_account_id)


@pytest.fixture(scope="session")
def gym_id() -> UUID:
    """The single seeded gym (deterministic; see tests/seed_constants.py).

    There is exactly one seeded gym (NUM_GYMS = 1) on the shared test Stripe
    Connect account, so integration tests always target it. This fixture just
    hands back its hardcoded id — it never creates, looks up, or deletes a gym
    (deleting the seeded gym would corrupt the seed). Tests that create members /
    discounts clean up the specific rows they add (e.g. ``delete_member_data``).
    """
    return UUID(SEEDED_GYM_ID)
