"""Members module fixtures — compose member management service from primitives."""

import pytest

from src.core.config import settings
from src.members.service.crm_member_services.members_crm_members_list_service import (  # noqa: E501
    CrmMembersListService,
)
from src.members.service.crm_member_services.members_crm_total_counts_service import (  # noqa: E501
    CrmTotalCountsService,
)
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


@pytest.fixture(scope="module")
def crm_members_list_service(db_pool):
    """The real members-list orchestrator (no Stripe dependency).

    Wired exactly as ``core/dependencies.py`` wires it, so a view test runs
    the same SQL the endpoint does.
    """
    return CrmMembersListService(db_pool, settings.member_dormancy_days)


@pytest.fixture(scope="module")
def total_counts_service(db_pool):
    """The real subtitle-tally service (no Stripe dependency)."""
    return CrmTotalCountsService(db_pool, settings.member_dormancy_days)
