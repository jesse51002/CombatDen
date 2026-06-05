"""Discounts module fixtures."""

import pytest

from tests.helpers.service_factory import build_discounts_service


@pytest.fixture(scope="module")
def discounts_service(db_pool):
    return build_discounts_service(db_pool)
