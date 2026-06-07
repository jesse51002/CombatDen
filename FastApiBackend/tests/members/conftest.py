"""Members module fixtures — compose member management service from primitives."""

import pytest

from tests.helpers.service_factory import (
    build_member_management_service,
    build_member_memberships_service,
)


@pytest.fixture(scope="module")
def management_service(db_pool, stripe_client):
    return build_member_management_service(db_pool, stripe_client)


@pytest.fixture(scope="module")
def memberships_service(db_pool, stripe_client):
    """Needed by linked-account tests that start memberships."""
    return build_member_memberships_service(db_pool, stripe_client)
