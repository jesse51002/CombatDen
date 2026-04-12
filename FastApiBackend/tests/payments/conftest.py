"""Payments module fixtures — compose payment services from primitives."""

import pytest

from tests.helpers.service_factory import PaymentServices, build_payment_services


@pytest.fixture(scope="module")
def payment_services(stripe_client):
    return build_payment_services(stripe_client)


@pytest.fixture(scope="module")
def price_service(payment_services):
    return payment_services.price


@pytest.fixture(scope="module")
def membership_service(payment_services):
    return payment_services.membership


@pytest.fixture(scope="module")
def discount_service(payment_services):
    return payment_services.discount


@pytest.fixture(scope="module")
def members_service(payment_services):
    return payment_services.members


@pytest.fixture(scope="module")
def subscription_service(payment_services):
    return payment_services.subscription


@pytest.fixture(scope="module")
def payment_service(payment_services):
    return payment_services.payment
