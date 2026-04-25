"""Stripe Test Clock helpers for time-simulation tests.

Standalone module — no pytest imports, no fixture dependencies.
Every function accepts its dependencies as parameters.
"""

import asyncio
from datetime import UTC, datetime

import stripe

from src.payments.service.payments_stripe_client import PaymentsStripeClient

POLL_INTERVAL_S = 1.0
POLL_MAX_WAIT_S = 60


async def create_test_clock(
    stripe_client: PaymentsStripeClient,
    frozen_time: datetime,
    connect_opts: stripe.RequestOptions,
) -> str:
    """Create a Stripe test clock frozen at ``frozen_time``.

    Args:
        stripe_client: Configured Stripe client.
        frozen_time: The initial time the clock is frozen at (must be UTC).
        connect_opts: Stripe Connect request options.

    Returns:
        The test clock ID.
    """
    ts = int(frozen_time.replace(tzinfo=UTC).timestamp())
    clock = await stripe_client.client.v1.test_helpers.test_clocks.create_async(
        params={"frozen_time": ts, "name": "integration-test"},
        options=connect_opts,
    )
    return clock.id


async def advance_clock(
    stripe_client: PaymentsStripeClient,
    clock_id: str,
    advance_to: datetime,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Advance a test clock and poll until it is ready.

    Args:
        stripe_client: Configured Stripe client.
        clock_id: The test clock to advance.
        advance_to: Target time (UTC).
        connect_opts: Stripe Connect request options.

    Raises:
        RuntimeError: If the clock enters ``internal_failure``.
        TimeoutError: If the clock does not become ready within the timeout.
    """
    ts = int(advance_to.replace(tzinfo=UTC).timestamp())
    await stripe_client.client.v1.test_helpers.test_clocks.advance_async(
        clock_id,
        params={"frozen_time": ts},
        options=connect_opts,
    )

    elapsed = 0.0
    while elapsed < POLL_MAX_WAIT_S:
        clock = await stripe_client.client.v1.test_helpers.test_clocks.retrieve_async(
            clock_id,
            options=connect_opts,
        )
        if clock.status == "ready":
            return
        if clock.status == "internal_failure":
            raise RuntimeError(f"Test clock {clock_id} entered internal_failure")
        await asyncio.sleep(POLL_INTERVAL_S)
        elapsed += POLL_INTERVAL_S

    raise TimeoutError(f"Test clock {clock_id} did not become ready within {POLL_MAX_WAIT_S}s")


async def delete_test_clock(
    stripe_client: PaymentsStripeClient,
    clock_id: str,
    connect_opts: stripe.RequestOptions,
) -> None:
    """Delete a test clock (cleans up all attached resources)."""
    await stripe_client.client.v1.test_helpers.test_clocks.delete_async(
        clock_id,
        options=connect_opts,
    )
