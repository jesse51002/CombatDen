"""Integration tests for the ``account.updated`` handler.

Verifies that the canonical mapper's status is written to
``gyms.stripe_onboarding_status`` for each connected-account state.

The ``disabled`` case is a regression guard: the handler used to map a
disabled account to ``status="disabled"``, which the column's old CHECK
constraint rejected — the write raised a constraint violation and Stripe
retried forever. ``disabled`` is now a legal enum value.
"""

from sqlalchemy import text

from tests.stripe_webhooks.event_builders import make_account_updated_event


async def _fetch_status(db_pool, gym_id) -> str | None:
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT stripe_onboarding_status FROM gyms WHERE gym_id = :id"),
            {"id": str(gym_id)},
        )
        row = result.mappings().fetchone()
    return str(row["stripe_onboarding_status"]) if row else None


async def test_account_updated_disabled_reason_writes_disabled(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
):
    """A disabled_reason maps to 'disabled' (previously a CHECK violation)."""
    event = make_account_updated_event(
        stripe_account_id=stripe_account_id,
        details_submitted=True,
        charges_enabled=False,
        payouts_enabled=False,
        disabled_reason="requirements.past_due",
        currently_due=["external_account"],
    )

    await stripe_webhooks_service.handle_event(event)

    assert await _fetch_status(db_pool, gym_id) == "disabled"


async def test_account_updated_fully_enabled_writes_complete(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
):
    """All capabilities enabled + no disabled_reason maps to 'complete'.

    The gym is first driven to 'pending' so the assertion proves the
    handler wrote 'complete' rather than reading the seeded value.
    """
    await stripe_webhooks_service.handle_event(
        make_account_updated_event(
            stripe_account_id=stripe_account_id,
            details_submitted=False,
            charges_enabled=False,
            payouts_enabled=False,
        )
    )
    assert await _fetch_status(db_pool, gym_id) == "pending"

    await stripe_webhooks_service.handle_event(
        make_account_updated_event(
            stripe_account_id=stripe_account_id,
            details_submitted=True,
            charges_enabled=True,
            payouts_enabled=True,
        )
    )
    assert await _fetch_status(db_pool, gym_id) == "complete"


async def test_account_updated_incomplete_writes_pending(
    stripe_webhooks_service,
    db_pool,
    stripe_account_id,
    gym_id,
):
    """Onboarding not finished (no disabled_reason) maps to 'pending'."""
    event = make_account_updated_event(
        stripe_account_id=stripe_account_id,
        details_submitted=True,
        charges_enabled=False,
        payouts_enabled=False,
        currently_due=["external_account"],
    )

    await stripe_webhooks_service.handle_event(event)

    assert await _fetch_status(db_pool, gym_id) == "pending"
