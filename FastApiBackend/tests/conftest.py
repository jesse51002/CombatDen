"""Root conftest — infrastructure primitives only.

Provides session-scoped building blocks (db_pool, stripe_client,
stripe_account_id, gym_id, connect_opts). Module confests compose
domain services from these primitives via ``service_factory``.
"""

from uuid import UUID

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.core.config import settings
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.database import DirectDatabasePool
from tests.helpers.cleanup import delete_all_gym_data

# Persistent Stripe Custom Connect account for integration tests.
# Created once via script, reused across all test runs (no 50s wait).
# Production uses Express accounts — Custom is only for testing so we
# can programmatically fill onboarding requirements.
# To recreate: poetry run python tests/scripts/create_test_account.py
STRIPE_TEST_ACCOUNT_ID = "acct_1TLWP5LArmKROnJ8"


# ── Database ────────────────────────────────────────────────────


@pytest.fixture(scope="session")
def db_pool():
    """Session-wide async database pool."""
    pool = DirectDatabasePool()
    yield pool
    # Engine disposal is sync-safe in teardown context


# ── Stripe ──────────────────────────────────────────────────────


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
    """Stripe Connect request options for the test account.

    Uses the read-only variant (no ``idempotency_key``) because test
    helpers that call Stripe directly (``create_member`` / ``create_plan``
    / retrievals) do not need dedup semantics and reuse the same opts
    across many calls. Production code paths always go through
    ``connect_opts`` with a per-request idempotency key.
    """
    return PaymentsStripeClient.connect_opts_readonly(stripe_account_id)


# ── Test gym ────────────────────────────────────────────────────


@pytest.fixture(scope="session")
async def gym_id(db_pool, stripe_account_id):
    """Insert a test gym row linked to the test Stripe Connect account.

    Teardown deletes all child data, then the gym row itself.
    """
    insert_sql = """
        INSERT INTO gyms (gym_name, stripe_account_id, stripe_onboarding_status)
        VALUES (:name, :stripe_account_id, 'complete')
        RETURNING gym_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(insert_sql),
            {"name": "Integration Test Gym", "stripe_account_id": stripe_account_id},
        )
        row = result.mappings().fetchone()
        await session.commit()

    gid = UUID(str(row["gym_id"]))
    yield gid

    # Teardown: remove all child rows, then the gym
    await delete_all_gym_data(db_pool, gid)
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM gyms WHERE gym_id = :gym_id"),
            {"gym_id": str(gid)},
        )
        await session.commit()
