"""Membership plans module fixtures."""

import pytest

from tests.helpers.service_factory import build_membership_plans_service


@pytest.fixture(scope="module")
def plans_service(db_pool, stripe_client):
    return build_membership_plans_service(db_pool, stripe_client)
