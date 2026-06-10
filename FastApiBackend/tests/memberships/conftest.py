"""Member memberships module fixtures — compose services from primitives."""

import pytest

from tests.helpers.service_factory import (
    build_member_management_service,
    build_member_memberships_service,
    build_membership_plans_service,
    build_payment_services,
    build_payment_sync_service,
)


@pytest.fixture(scope="module")
def memberships_service(db_pool, stripe_client):
    return build_member_memberships_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def payment_sync_service(db_pool, stripe_client):
    """Expose PaymentSyncService for tests that need to
    trigger a standalone resync after state has already been set up.

    Linked-discount recalculation is gone — the sync now reads the frozen
    applied-discount rows and computes each consolidated line's coupon at
    sync-time.
    """
    return build_payment_sync_service(db_pool, stripe_client)


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
