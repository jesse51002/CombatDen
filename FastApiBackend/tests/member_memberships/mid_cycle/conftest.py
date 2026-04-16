"""Mid-cycle edit test fixtures.

The discount-cascade tests drive the public ``DiscountsService``
(not just the payment-sync layer) so the real delete path is
exercised, including its background-task fan-out.
"""

import pytest

from tests.helpers.service_factory import build_discounts_service


@pytest.fixture(scope="module")
def discounts_service(db_pool, stripe_client):
    return build_discounts_service(db_pool, stripe_client)
