"""Mid-cycle edit test fixtures.

The discount tests drive the public ``DiscountsService`` so the real
preset CRUD path (coupon-free, no cascade) is exercised end to end.
"""

import pytest

from tests.helpers.service_factory import build_discounts_service


@pytest.fixture(scope="module")
def discounts_service(db_pool):
    return build_discounts_service(db_pool)
