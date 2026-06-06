"""Build service instances from infrastructure primitives.

Mirrors the DI wiring in ``src/core/dependencies.py`` but as plain
functions — no container, no framework. Each ``build_*`` function
constructs the full internal dependency chain so callers only need
to pass ``db_pool`` and/or ``stripe_client``.

Standalone module — no pytest imports, no fixture dependencies.
"""

from dataclasses import dataclass

from src.discounts.service.discounts.discounts_service import DiscountsService
from src.member_memberships.service.memberships.member_memberships_service import (
    MemberMembershipsService,
)
from src.member_memberships.service.payment_sync.payment_sync_service import (
    PaymentSyncService,
)
from src.members.service.management.members_management_service import (
    MembersManagementService,
)
from src.membership_plans.service.plans.membership_plans_service import (
    MembershipPlansService,
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
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService

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
    payment = PaymentsStripePaymentService(stripe_client, members, price)
    return PaymentServices(
        price=price,
        membership=membership,
        discount=discount,
        members=members,
        subscription=subscription,
        payment=payment,
    )


def build_payment_sync_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> PaymentSyncService:
    """Build the membership payment-sync service.

    Mirrors ``src/core/dependencies.py`` (payment_sync_service).
    Linked-discount recalculation is gone — family discounts are frozen
    snapshot rows divided across the consolidated line at sync, and the
    sync-time coupon step uses ``stripe_client`` directly.
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
    return PaymentSyncService(
        db_pool,
        subscription_svc,
        gym_stripe_svc,
        stripe_client,
    )


def build_member_management_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembersManagementService:
    """Build the member management service.

    Mirrors ``src/core/dependencies.py`` (members_management_service).
    """
    members_svc = PaymentsStripeMembersService(stripe_client)
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    return MembersManagementService(db_pool, members_svc, sync_svc)


def build_member_memberships_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsService:
    """Build the full memberships service chain.

    Mirrors ``src/core/dependencies.py`` (member_memberships_service).
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    payment_svc = PaymentsStripePaymentService(
        stripe_client,
        members_svc,
        price_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    return MemberMembershipsService(
        db_pool,
        sync_svc,
        payment_svc,
        gym_stripe_svc,
    )


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
    sync_svc = build_payment_sync_service(db_pool, stripe_client)
    discounts_svc = build_discounts_service(db_pool)
    return MembershipPlansService(
        db_pool,
        gym_stripe_svc,
        membership_svc,
        price_svc,
        sync_svc,
        discounts_svc,
    )
