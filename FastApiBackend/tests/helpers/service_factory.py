"""Build service instances from infrastructure primitives.

Mirrors the DI wiring in ``src/core/dependencies.py`` but as plain
functions — no container, no framework. Each ``build_*`` function
constructs the full internal dependency chain so callers only need
to pass ``db_pool`` and/or ``stripe_client``.

Standalone module — no pytest imports, no fixture dependencies.
"""

from dataclasses import dataclass
from uuid import UUID

from schema.task import ProrationBehavior, TaskType

from src.discounts.service.discounts_service import DiscountsService
from src.members.service.management.members_management_service import (
    MembersManagementService,
)
from src.memberships.service.memberships_invoice_fetch import (
    MemberMembershipsInvoiceFetch,
)
from src.memberships.service.memberships_invoice_fetch_runner import (
    MembershipsInvoiceFetchRunner,
)
from src.memberships.service.memberships_reprice import (
    MemberMembershipsReprice,
)
from src.memberships.service.memberships_service import (
    MemberMembershipsService,
)
from src.memberships.service.memberships_upgrade import (
    MemberMembershipsUpgrade,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_membership_service import (
    PaymentsStripeMembershipService,
)
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.plans.service.plans_service import (
    MembershipPlansService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.payer_resolver import PayerResolver
from src.shared.paying_member_lock import PayingMemberLock
from src.stripe_webhooks.service.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)
from src.stripe_webhooks.service.refund_handler import RefundHandler
from src.sync.service.sync_builder import (
    PaymentSyncBuilder,
)
from src.sync.service.sync_discounts import (
    PaymentSyncDiscounts,
)
from src.sync.service.sync_freeze import (
    PaymentSyncFreeze,
)
from src.sync.service.sync_one_time import (
    PaymentSyncOneTime,
)
from src.sync.service.sync_service import (
    PaymentSyncService,
)
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_membership_reprice_handler import (
    MembershipRepriceTaskHandler,
)
from src.tasks.service.tasks_service import TasksService
from src.waivers.service.waivers.waivers_service import WaiversService

# ── Payment services namespace ──────────────────────────────────


@dataclass(frozen=True)
class PaymentServices:
    """All six Stripe payment services in one namespace."""

    price: PaymentsStripePriceService
    membership: PaymentsStripeMembershipService
    discount: PaymentsStripeDiscountService
    members: PaymentsStripeMembersService
    subscription: PaymentsStripeSubscriptionService
    payment: PaymentsStripePaymentService


# ── Builder functions ───────────────────────────────────────────


def build_payment_services(stripe_client: PaymentsStripeClient) -> PaymentServices:
    """Build all six payment services.

    Mirrors ``src/core/dependencies.py`` lines 117-151.
    """
    price = PaymentsStripePriceService(stripe_client)
    membership = PaymentsStripeMembershipService(stripe_client, price)
    discount = PaymentsStripeDiscountService(stripe_client)
    members = PaymentsStripeMembersService(stripe_client)
    subscription = PaymentsStripeSubscriptionService(
        stripe_client,
        members,
        price,
        discount,
    )
    payment = PaymentsStripePaymentService(stripe_client, members)
    return PaymentServices(
        price=price,
        membership=membership,
        discount=discount,
        members=members,
        subscription=subscription,
        payment=payment,
    )


def build_paying_member_lock(
    db_pool: DirectDatabasePool,
) -> PayingMemberLock:
    """Build the payer concurrency lock (mirrors dependencies.py)."""
    return PayingMemberLock(db_pool)


def build_payment_sync_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> PaymentSyncService:
    """Build the membership payment-sync service.

    Mirrors ``src/core/dependencies.py`` (payment_sync_service). PaymentSyncService
    is a thin orchestrator: it takes the shared ``PayerResolver``, the
    ``PaymentSyncFreeze`` sub-service, and a
    ``PaymentSyncBuilder`` (which itself owns a ``PaymentSyncDiscounts`` coupon
    engine), and builds its Stripe-dispatch + writeback halves internally.
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client,
        members_svc,
        price_svc,
        discount_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    payer_resolver = PayerResolver(db_pool, gym_stripe_svc)
    discounts = PaymentSyncDiscounts(discount_svc)
    builder = PaymentSyncBuilder(db_pool, discounts)
    paying_lock = PayingMemberLock(db_pool)
    return PaymentSyncService(
        db_pool,
        subscription_svc,
        payer_resolver,
        builder,
        paying_lock,
    )


def build_member_management_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembersManagementService:
    """Build the member management service.

    Mirrors ``src/core/dependencies.py`` (members_management_service).
    """
    members_svc = PaymentsStripeMembersService(stripe_client)
    price_svc = PaymentsStripePriceService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client,
        members_svc,
        price_svc,
        discount_svc,
    )
    return MembersManagementService(db_pool, members_svc, subscription_svc)


def build_invoice_fetch(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsInvoiceFetch:
    """Build the on-demand / reconciler invoice fetch engine.

    Mirrors ``src/core/dependencies.py`` (member_memberships_invoice_fetch).
    """
    payer_resolver = PayerResolver(db_pool, GymStripeService(db_pool))
    return MemberMembershipsInvoiceFetch(
        db_pool,
        stripe_client,
        InvoicePaidHandler(stripe_client=stripe_client),
        InvoicePaymentPaidHandler(stripe_client=stripe_client),
        InvoicePaymentFailedHandler(),
        RefundHandler(),
        payer_resolver,
    )


def build_invoice_fetch_runner(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembershipsInvoiceFetchRunner:
    """Build the fire-and-forget post-op invoice-fetch runner."""
    return MembershipsInvoiceFetchRunner(
        build_invoice_fetch(db_pool, stripe_client)
    )


def build_member_memberships_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsService:
    """Build the full memberships service chain.

    Mirrors ``src/core/dependencies.py`` (member_memberships_service). The
    on-demand invoice fetch the facade fires is a no-op in tests unless
    ``settings.invoice_fetch_on_demand_enabled`` is set (conftest disables it),
    so ops don't kick off real background Stripe fetches.
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    payment_svc = PaymentsStripePaymentService(
        stripe_client,
        members_svc,
    )
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client,
        members_svc,
        price_svc,
        discount_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    payer_resolver = PayerResolver(db_pool, gym_stripe_svc)
    freeze_service = PaymentSyncFreeze(subscription_svc)
    paying_lock = PayingMemberLock(db_pool)
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    one_time_svc = PaymentSyncOneTime(
        db_pool,
        discounts=PaymentSyncDiscounts(discount_svc),
        payment_service=payment_svc,
        payer_resolver=payer_resolver,
    )
    discounts_svc = DiscountsService(db_pool)
    management_svc = build_member_management_service(
        db_pool,
        stripe_client,
    )
    waivers_svc = WaiversService(db_pool)
    return MemberMembershipsService(
        db_pool,
        sync_svc,
        payment_svc,
        gym_stripe_svc,
        payer_resolver,
        freeze_service,
        paying_lock,
        one_time_svc,
        discounts_svc,
        build_memberships_reprice(db_pool, stripe_client),
        build_memberships_upgrade(db_pool, stripe_client),
        management_svc,
        waivers_svc,
        build_invoice_fetch_runner(db_pool, stripe_client),
    )


def build_membership_reprice_task_handler(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembershipRepriceTaskHandler:
    """Build the membership_reprice task handler (the tasks↔memberships glue).

    Mirrors ``src/core/dependencies.py`` (membership_reprice_task_handler).
    """
    return MembershipRepriceTaskHandler(
        db_pool=db_pool,
        reprice_service=build_memberships_reprice(db_pool, stripe_client),
        tasks_service=TasksService(db_pool),
    )


def build_tasks_executor(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> TasksExecutor:
    """Build the tasks executor with the reprice handler registered.

    Mirrors ``src/core/dependencies.py`` (tasks_executor).
    """
    return TasksExecutor(
        db_pool,
        handlers={
            TaskType.membership_reprice: (
                build_membership_reprice_task_handler(db_pool, stripe_client)
            ),
        },
    )


def build_memberships_reprice(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsReprice:
    """Build the task-agnostic reprice service.

    Mirrors ``src/core/dependencies.py`` (memberships_reprice).
    """
    gym_stripe_svc = GymStripeService(db_pool)
    paying_lock = build_paying_member_lock(db_pool)
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    return MemberMembershipsReprice(
        db_pool=db_pool,
        payment_sync_service=sync_svc,
        gym_stripe_service=gym_stripe_svc,
        paying_lock=paying_lock,
    )


def build_memberships_upgrade(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsUpgrade:
    """Build the cross-plan upgrade service.

    Mirrors ``src/core/dependencies.py`` (memberships_upgrade).
    """
    gym_stripe_svc = GymStripeService(db_pool)
    paying_lock = build_paying_member_lock(db_pool)
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    return MemberMembershipsUpgrade(
        db_pool=db_pool,
        payment_sync_service=sync_svc,
        gym_stripe_service=gym_stripe_svc,
        paying_lock=paying_lock,
    )


async def batch_reprice_plan(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
    gym_id: UUID,
    plan_id: UUID,
    proration_behavior: ProrationBehavior = ProrationBehavior.no_charge,
) -> tuple[UUID | None, int]:
    """Run a per-plan batch reprice exactly as ``POST /reprice-plan`` does.

    Mirrors the router: discover the plan's memberships to upgrade, create
    one task, fire the background run. Returns ``(task_id, count)`` —
    ``(None, 0)`` when nothing needs upgrading. Poll with
    ``await_task_terminal``.
    """
    handler = build_membership_reprice_task_handler(db_pool, stripe_client)
    executor = build_tasks_executor(db_pool, stripe_client)
    task_id, count = await handler.create_batch(gym_id, plan_id, proration_behavior)
    if task_id is not None:
        executor.start_in_background(task_id)
    return task_id, count


def build_discounts_service(
    db_pool: DirectDatabasePool,
) -> DiscountsService:
    """Build the discounts service.

    Presets are plain, coupon-free gym config: no Stripe, no payment sync —
    the service takes only ``db_pool``. Mirrors
    ``src/core/dependencies.py`` (discounts_service).
    """
    return DiscountsService(db_pool)


def build_membership_plans_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembershipPlansService:
    """Build the membership plans service.

    Mirrors ``src/core/dependencies.py`` (membership_plans_service).
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    membership_svc = PaymentsStripeMembershipService(stripe_client, price_svc)
    gym_stripe_svc = GymStripeService(db_pool)
    discounts_svc = build_discounts_service(db_pool)
    return MembershipPlansService(
        db_pool,
        gym_stripe_svc,
        membership_svc,
        price_svc,
        discounts_svc,
    )
