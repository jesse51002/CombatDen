"""Build service instances from infrastructure primitives.

Mirrors the DI wiring in ``src/core/dependencies.py`` but as plain
functions — no container, no framework. Each ``build_*`` function
constructs the full internal dependency chain so callers only need
to pass ``db_pool`` and/or ``stripe_client``.

Standalone module — no pytest imports, no fixture dependencies.
"""

from dataclasses import dataclass

from src.discounts.service.discounts_service import DiscountsService
from src.member_memberships.service.linked_member_discount_service import (
    LinkedMemberDiscountService,
)
from src.member_memberships.service.member_memberships_service import (
    MemberMembershipsService,
)
from src.member_memberships.service.membership_payment_sync_service import (
    MembershipPaymentSyncService,
)
from src.members.service.members_management_service import (
    MembersManagementService,
)
from src.membership_plans.service.membership_plans_service import (
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
        stripe_client, members, price, discount,
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


def build_member_management_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembersManagementService:
    """Build the member management service.

    Mirrors ``src/core/dependencies.py`` lines 174-178.
    """
    members_svc = PaymentsStripeMembersService(stripe_client)
    return MembersManagementService(db_pool, members_svc)


def build_member_memberships_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MemberMembershipsService:
    """Build the full memberships service chain.

    Mirrors ``src/core/dependencies.py`` lines 153-173.
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client, members_svc, price_svc, discount_svc,
    )
    payment_svc = PaymentsStripePaymentService(
        stripe_client, members_svc, price_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    linked_discount_svc = LinkedMemberDiscountService(db_pool)
    sync_svc = MembershipPaymentSyncService(
        db_pool, subscription_svc, gym_stripe_svc, linked_discount_svc,
    )
    return MemberMembershipsService(
        db_pool, sync_svc, payment_svc, gym_stripe_svc,
    )


def build_discounts_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> DiscountsService:
    """Build the discounts service.

    Mirrors ``src/core/dependencies.py`` lines 180-186.
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client, members_svc, price_svc, discount_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    linked_discount_svc = LinkedMemberDiscountService(db_pool)
    sync_svc = MembershipPaymentSyncService(
        db_pool, subscription_svc, gym_stripe_svc, linked_discount_svc,
    )
    return DiscountsService(db_pool, gym_stripe_svc, discount_svc, sync_svc)


def build_membership_plans_service(
    db_pool: DirectDatabasePool,
    stripe_client: PaymentsStripeClient,
) -> MembershipPlansService:
    """Build the membership plans service.

    Mirrors ``src/core/dependencies.py`` lines 188-195.
    """
    price_svc = PaymentsStripePriceService(stripe_client)
    members_svc = PaymentsStripeMembersService(stripe_client)
    discount_svc = PaymentsStripeDiscountService(stripe_client)
    membership_svc = PaymentsStripeMembershipService(stripe_client, price_svc)
    subscription_svc = PaymentsStripeSubscriptionService(
        stripe_client, members_svc, price_svc, discount_svc,
    )
    gym_stripe_svc = GymStripeService(db_pool)
    linked_discount_svc = LinkedMemberDiscountService(db_pool)
    sync_svc = MembershipPaymentSyncService(
        db_pool, subscription_svc, gym_stripe_svc, linked_discount_svc,
    )
    return MembershipPlansService(
        db_pool, gym_stripe_svc, membership_svc, price_svc, sync_svc,
    )
