"""Members module fixtures — compose member management service from primitives."""

import pytest

from tests.helpers.service_factory import build_member_management_service


@pytest.fixture(scope="module")
def management_service(db_pool, stripe_client):
    return build_member_management_service(db_pool, stripe_client)
