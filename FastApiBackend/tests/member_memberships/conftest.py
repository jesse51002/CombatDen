"""Member memberships module fixtures — compose services from primitives."""

import pytest

from tests.helpers.service_factory import (
    build_member_memberships_service,
    build_membership_plans_service,
    build_payment_services,
)


@pytest.fixture(scope="module")
def memberships_service(db_pool, stripe_client):
    return build_member_memberships_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def plans_service(db_pool, stripe_client):
    return build_membership_plans_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def payment_services(stripe_client):
    """Expose payment services for tests that verify Stripe state directly."""
    return build_payment_services(stripe_client)
