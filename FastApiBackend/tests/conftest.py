"""Root conftest — TestClient + mock auth + mock DB-pool fixtures (unit tests)
AND session-scoped integration-test infrastructure (db_pool, stripe_client,
stripe_account_id, gym_id, connect_opts).

Unit tests use the TestClient/AsyncMock fixtures.
Integration / billing tests use the session-scoped Stripe + DB fixtures.
"""

from collections.abc import AsyncGenerator, Generator
from dataclasses import dataclass, field
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
import stripe
from fastapi.testclient import TestClient

# (isort: skip stops import-sorting from reordering `schema` ahead of it).
import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.gym_employee import EmployeeType  # isort: skip

from src.core.config import settings
from src.main import app
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool
from tests.helpers import cleanup
from tests.helpers.data_factory import (
    TestDiscount,
    TestMember,
    TestPlan,
    TestReward,
    create_discount,
    create_member,
    create_payment_method,
    create_plan,
    create_reward,
)
from tests.helpers.stripe_clock import create_test_clock, delete_test_clock
from tests.seed_constants import SEEDED_GYM_ID

# Never start the reconciler's APScheduler when a test boots the app via
# ``with TestClient(app)`` (which runs the lifespan). The reconciler is exercised
# directly in tests/reconciler/ by calling the services.
settings.reconciler_enabled = False


@pytest.fixture(autouse=True)
def _disable_on_demand_invoice_fetch() -> Generator[None]:
    """Ops do NOT fire real background Stripe invoice fetches in tests by
    default (the post-op on-demand fast-path). The dedicated invoice-fetch
    tests drive ``fetch_for_payer`` / the runner directly; everything else stays
    deterministic and makes no extra Stripe calls on that path."""
    prev = settings.invoice_fetch_on_demand_enabled
    settings.invoice_fetch_on_demand_enabled = False
    yield
    settings.invoice_fetch_on_demand_enabled = prev


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
def fake_employee_id() -> str:
    """A stable fake employee id for ``get_employee_id*`` returns."""
    return str(uuid4())


@pytest.fixture
def auth_mock(fake_user_id: str, fake_employee_id: str) -> MagicMock:
    """An ``Auth`` double that always succeeds.

    ``get_current_user`` returns a payload carrying both ``sub``
    (=``fake_user_id``) and an ``email`` claim — identity is the verified
    email now. The gates are async no-ops, except ``verify_roles`` which
    returns a concrete ``EmployeeType`` so handlers that use the matched
    role keep working, ``get_employee_id`` / ``get_employee_id_for_member``
    which return a fixed fake employee UUID, and
    ``verify_verified_account`` which returns the payload's email.
    """
    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": fake_user_id,
        "email": "test@example.com",
    }
    auth.verify_roles = AsyncMock(return_value=EmployeeType.owner)
    auth.verify_gym_owner = AsyncMock(return_value=None)
    auth.verify_gym_admin_or_owner = AsyncMock(return_value=None)
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    auth.verify_member_self = AsyncMock(return_value=None)
    auth.verify_verified_account = AsyncMock(
        return_value="test@example.com"
    )
    auth.verify_staff_principal = AsyncMock(return_value=None)
    auth.get_employee_id = AsyncMock(return_value=UUID(fake_employee_id))
    auth.get_employee_id_for_member = AsyncMock(
        return_value=UUID(fake_employee_id)
    )
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
    name: str = "White",
    image_url: str | None = None,
    classes_to_next_major: int = 15,
    sub_rank_count: int = 0,
    sub_rank_image_overrides: dict | None = None,
    created_at: datetime | None = None,
) -> dict:
    """A gym_ranks-row dict shaped to match SQL RETURNING clauses.

    One row per MAIN rank (two-level model): a single ``name`` plus the
    per-gym sub-rank machinery (``sub_rank_count`` + the persist-only
    ``sub_rank_image_overrides`` map). Sub-rank labels are derived from
    the gym's ``sub_rank_type`` at read time, so no sub name/order/color
    is carried here. Matches ``RankResponse``.
    """
    return {
        "rank_id": rank_id,
        "gym_id": gym_id,
        "main_rank_num_order": main_rank_num_order,
        "name": name,
        "image_url": image_url,
        "classes_to_next_major": classes_to_next_major,
        "sub_rank_count": sub_rank_count,
        "sub_rank_image_overrides": (
            sub_rank_image_overrides
            if sub_rank_image_overrides is not None
            else {}
        ),
        "created_at": created_at or datetime.now(UTC),
    }


def make_reward_row(
    *,
    reward_id: str,
    gym_id: str,
    title: str = "Free smoothie",
    point_cost: int = 50,
    # gym_rewards.price_label / image_url are NOT NULL — default to
    # realistic non-null values so callers that don't care about these
    # fields don't have to pass them.
    price_label: str = "Free",
    image_url: str = "https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg?auto=compress&cs=tinysrgb&w=1200",
    is_active: bool = True,
    created_at: datetime | None = None,
) -> dict:
    return {
        "reward_id": reward_id,
        "gym_id": gym_id,
        "title": title,
        "point_cost": point_cost,
        "price_label": price_label,
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
    return PaymentsStripeClient(
        secret_key=settings.stripe_secret_key,
        api_version=settings.stripe_api_version,
    )


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


# ──────────────────────────────────────────────────────────────────
# Created-resource registry + auto-cleanup (function-scoped)
# Any data-creating integration test tracks what it makes here; the
# fixture deletes EXACTLY those rows / Stripe objects on teardown, in
# FK-safe order, best-effort. It never deletes by gym_id and never
# touches the seeded gym, its Stripe account, or any seed object.
# ──────────────────────────────────────────────────────────────────


@dataclass
class CreatedResources:
    """Records what a test created so teardown can remove just those.

    Two ways to register:
      * ``await created.member(...)`` / ``.plan(...)`` / ``.discount(...)``
        / ``.reward(...)`` / ``.test_clock(...)`` — thin wrappers over the
        data_factory / stripe_clock helpers that create AND track in one
        call.
      * ``created.track_customer(id)`` / ``track_product`` / ``track_price``
        / ``track_coupon`` / ``track_reward`` / ``track_redemption`` /
        ``track_employee`` / ``track_auth_user`` — for tests that drive
        services directly (or call the live API) and get ids back on the
        response.
    """

    db_pool: DirectDatabasePool
    stripe_client: PaymentsStripeClient
    connect_opts: stripe.RequestOptions
    members: list[UUID] = field(default_factory=list)
    plan_db_ids: list[UUID] = field(default_factory=list)
    # plan_id -> (stripe_product_id, stripe_price_id); archived only after
    # the plan's DB row deletes successfully (see cleanup).
    plan_stripe_ids: dict[UUID, tuple[str, str]] = field(default_factory=dict)
    discounts: list[UUID] = field(default_factory=list)
    clocks: list[str] = field(default_factory=list)
    stripe_customers: list[str] = field(default_factory=list)
    stripe_products: list[str] = field(default_factory=list)
    stripe_prices: list[str] = field(default_factory=list)
    stripe_coupons: list[str] = field(default_factory=list)
    rewards: list[UUID] = field(default_factory=list)
    # A redemption row FKs both a member and a reward — always deleted
    # first in cleanup(), before either.
    reward_redemptions: list[UUID] = field(default_factory=list)
    # Gym staff rows + the Supabase auth logins created for them. Neither
    # carries a Stripe object, and there is no FK between the two (identity is
    # email-based), so both are removed independently at teardown.
    employees: list[UUID] = field(default_factory=list)
    auth_users: list[str] = field(default_factory=list)

    # ── create-and-track wrappers ──────────────────────────────

    async def member(self, gym_id: UUID, **kwargs) -> TestMember:
        member = await create_member(
            self.db_pool, self.stripe_client, gym_id, self.connect_opts, **kwargs
        )
        self.members.append(member.member_id)
        # A clock-scoped customer is cascade-deleted with its clock; only
        # track non-clock customers for explicit deletion.
        if kwargs.get("test_clock_id") is None:
            self.stripe_customers.append(member.stripe_customer_id)
        return member

    async def plan(self, gym_id: UUID, **kwargs) -> TestPlan:
        plan = await create_plan(
            self.db_pool, self.stripe_client, gym_id, self.connect_opts, **kwargs
        )
        self.plan_db_ids.append(plan.plan_id)
        # Plan-owned Stripe ids are archived ONLY once the DB row actually
        # deletes (see cleanup) — never flat-track them here.
        self.plan_stripe_ids[plan.plan_id] = (
            plan.stripe_product_id,
            plan.stripe_price_id,
        )
        return plan

    async def discount(self, gym_id: UUID, **kwargs) -> TestDiscount:
        discount = await create_discount(self.db_pool, gym_id, **kwargs)
        self.discounts.append(discount.discount_id)
        return discount

    async def reward(self, gym_id: UUID, **kwargs) -> TestReward:
        reward = await create_reward(self.db_pool, gym_id, **kwargs)
        self.rewards.append(reward.reward_id)
        return reward

    async def payment_method(self) -> str:
        # Payment methods are intentionally not cleaned up (Stripe allows
        # unlimited test PMs and they cannot be deleted, only detached).
        return await create_payment_method(self.stripe_client, self.connect_opts)

    async def test_clock(self, frozen_time: datetime) -> str:
        clock_id = await create_test_clock(
            self.stripe_client, frozen_time, self.connect_opts
        )
        self.clocks.append(clock_id)
        return clock_id

    # ── manual trackers (service tests) ────────────────────────

    def track_member(self, member_id: UUID) -> None:
        self.members.append(member_id)

    def track_plan_db(self, plan_id: UUID) -> None:
        """Track a CRM plan row (membership_plans + its prices) for deletion.

        For Stripe product/price archival, also call ``track_product`` /
        ``track_price`` with the ids the service returned.
        """
        self.plan_db_ids.append(plan_id)

    def track_discount(self, discount_id: UUID) -> None:
        self.discounts.append(discount_id)

    def track_clock(self, clock_id: str) -> None:
        self.clocks.append(clock_id)

    def track_customer(self, customer_id: str) -> None:
        self.stripe_customers.append(customer_id)

    def track_product(self, product_id: str) -> None:
        self.stripe_products.append(product_id)

    def track_price(self, price_id: str) -> None:
        self.stripe_prices.append(price_id)

    def track_coupon(self, coupon_id: str) -> None:
        self.stripe_coupons.append(coupon_id)

    def track_reward(self, reward_id: UUID) -> None:
        self.rewards.append(reward_id)

    def track_redemption(self, redemption_id: UUID) -> None:
        self.reward_redemptions.append(redemption_id)

    def track_employee(self, employee_id: UUID) -> None:
        self.employees.append(employee_id)

    def track_auth_user(self, user_id: str) -> None:
        self.auth_users.append(user_id)

    # ── teardown ───────────────────────────────────────────────

    async def cleanup(self) -> None:
        """Delete everything tracked, FK-safe, best-effort.

        Order: Stripe clocks first (cascade their customers/subs/invoices)
        → redemption rows (FK both a member and a reward — must go before
        either) → DB members → plans → discounts → rewards → remaining
        Stripe customers → coupons → archive prices/products. Each step is
        isolated so one failure never blocks the rest or masks the test
        result.
        """
        for clock_id in self.clocks:
            await _safe(delete_test_clock(self.stripe_client, clock_id, self.connect_opts))

        for redemption_id in self.reward_redemptions:
            await _safe(
                cleanup.delete_reward_redemption(self.db_pool, redemption_id)
            )

        for member_id in self.members:
            await _safe(cleanup.delete_member_data(self.db_pool, member_id))
        for plan_id in self.plan_db_ids:
            deleted = await _safe_ok(
                cleanup.delete_plan_data(self.db_pool, plan_id)
            )
            stripe_ids = self.plan_stripe_ids.get(plan_id)
            if stripe_ids is None:
                continue
            if deleted:
                product_id, price_id = stripe_ids
                self.stripe_prices.append(price_id)
                self.stripe_products.append(product_id)
            else:
                # The DB row is stuck (e.g. a leftover membership FK) —
                # leave its Stripe price/product ACTIVE so the live-looking
                # plan stays usable instead of becoming a phantom that 500s
                # every start/preview ("price specified is inactive").
                import logging

                logging.getLogger(__name__).error(
                    "teardown: plan %s DB delete failed — leaving its "
                    "Stripe price/product active to avoid a live-DB/"
                    "archived-Stripe mismatch",
                    plan_id,
                )
        for discount_id in self.discounts:
            await _safe(cleanup.delete_discount_preset(self.db_pool, discount_id))

        for reward_id in self.rewards:
            await _safe(cleanup.delete_reward(self.db_pool, reward_id))

        # Staff rows + their auth logins — independent of member/Stripe data
        # (email-based identity, no FK between the two), so order is free.
        for employee_id in self.employees:
            await _safe(cleanup.delete_employee(self.db_pool, employee_id))
        for user_id in self.auth_users:
            await _safe(cleanup.delete_auth_user(self.db_pool, user_id))

        for customer_id in self.stripe_customers:
            await _safe(
                cleanup.delete_stripe_customer(
                    self.stripe_client, customer_id, self.connect_opts
                )
            )
        for coupon_id in self.stripe_coupons:
            await _safe(
                cleanup.delete_stripe_coupon(
                    self.stripe_client, coupon_id, self.connect_opts
                )
            )
        # Prices and products can only be archived (active=false), not
        # deleted. Archive prices before products.
        for price_id in self.stripe_prices:
            await _safe(
                cleanup.archive_stripe_price(
                    self.stripe_client, price_id, self.connect_opts
                )
            )
        for product_id in self.stripe_products:
            await _safe(
                cleanup.archive_stripe_product(
                    self.stripe_client, product_id, self.connect_opts
                )
            )


async def _safe_ok(coro) -> bool:
    """Like ``_safe``, but reports whether the step actually succeeded."""
    try:
        await coro
        return True
    except Exception as exc:  # noqa: BLE001 — teardown must never fail a test
        import logging

        logging.getLogger(__name__).warning("Test cleanup step failed: %s", exc)
        return False


async def _safe(coro) -> None:
    """Await a teardown coroutine, swallowing+logging any error."""
    try:
        await coro
    except Exception as exc:  # noqa: BLE001 — teardown must never fail a test
        import logging

        logging.getLogger(__name__).warning("Test cleanup step failed: %s", exc)


@pytest.fixture
async def created(
    db_pool, stripe_client, connect_opts
) -> AsyncGenerator[CreatedResources]:
    """Track created members/plans/discounts/clocks/Stripe objects and
    delete exactly those on teardown (FK-safe, best-effort)."""
    registry = CreatedResources(db_pool, stripe_client, connect_opts)
    try:
        yield registry
    finally:
        await registry.cleanup()
