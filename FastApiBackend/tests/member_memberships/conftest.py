"""Member memberships module fixtures — compose services from primitives."""

import pytest

from src.member_memberships.service.linked_member_discount_service import (
    LinkedMemberDiscountService,
)
from src.member_memberships.service.membership_payment_sync_service import (
    MembershipPaymentSyncService,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.gym_stripe_service import GymStripeService
from tests.helpers.service_factory import (
    build_member_management_service,
    build_member_memberships_service,
    build_membership_plans_service,
    build_payment_services,
)


@pytest.fixture(scope="module")
def memberships_service(db_pool, stripe_client):
    return build_member_memberships_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def payment_sync_service(db_pool, stripe_client):
    """Expose MembershipPaymentSyncService for tests that need to
    trigger a standalone resync after state has already been set up.
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
    linked_discount_svc = LinkedMemberDiscountService(db_pool)
    return MembershipPaymentSyncService(
        db_pool,
        subscription_svc,
        gym_stripe_svc,
        linked_discount_svc,
    )


@pytest.fixture(scope="module")
def plans_service(db_pool, stripe_client):
    return build_membership_plans_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def management_service(db_pool, stripe_client):
    """Member management service — used by linked-family writeback tests."""
    return build_member_management_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def payment_services(stripe_client):
    """Expose payment services for tests that verify Stripe state directly."""
    return build_payment_services(stripe_client)
