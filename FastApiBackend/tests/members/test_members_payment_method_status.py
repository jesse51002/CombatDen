"""Integration tests for the member payment-method-status read.

``MembersManagementService.has_payment_method`` backs
``GET /api/v1/members/{member_id}/payment-method-status``. Its failure
mode is asymmetric — a wrong ``True`` costs a hand-off, a wrong ``False``
invites a stranger's card onto an existing member's account — so these
tests are written against the false-negative direction: Stripe (not the
cached ``members.stripe_payment_method_id`` column) is the answer, and a
Stripe failure raises instead of reporting ``False``.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from sqlalchemy import text

from src.members.members_exceptions import MemberNotFoundError
from src.members.service.management.members_management_service import (
    MembersManagementService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from tests.helpers.cleanup import delete_member_data


@pytest.fixture(scope="module")
def payments_members_service(stripe_client):
    """The payments boundary primitive, wired as ``dependencies.py`` wires it."""
    return PaymentsStripeMembersService(stripe_client)


async def _read_payment_method_id(db_pool, member_id: UUID) -> str | None:
    """The CRM's cached default-card column for a member."""
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(
                        "SELECT stripe_payment_method_id FROM members "
                        "WHERE member_id = :id"
                    ),
                    {"id": str(member_id)},
                )
            )
            .mappings()
            .fetchone()
        )
    return row["stripe_payment_method_id"]


async def test_has_payment_method_true_when_card_attached(
    management_service,
    gym_id,
    created,
):
    """A member whose Stripe customer has a card attached reports True."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)

    assert await management_service.has_payment_method(member.member_id) is True


async def test_has_payment_method_false_when_nothing_attached(
    management_service,
    gym_id,
    created,
):
    """A member whose Stripe customer has nothing attached reports False."""
    member = await created.member(gym_id)

    assert await management_service.has_payment_method(member.member_id) is False


async def test_has_payment_method_false_when_no_stripe_customer(
    management_service,
    db_pool,
    gym_id,
):
    """No Stripe customer at all → False; nothing can be attached."""
    insert_sql = """
        INSERT INTO members (
            gym_id, first_name, last_name
        ) VALUES (:gym_id, 'NoCustomer', 'Member')
        RETURNING member_id
    """
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(insert_sql),
                    {"gym_id": str(gym_id)},
                )
            )
            .mappings()
            .fetchone()
        )
        await session.commit()
    member_id = UUID(str(row["member_id"]))

    try:
        assert await management_service.has_payment_method(member_id) is False
    finally:
        await delete_member_data(db_pool, member_id)


async def test_has_payment_method_reads_stripe_not_the_cached_column(
    management_service,
    payments_members_service,
    db_pool,
    gym_id,
    stripe_account_id,
    created,
):
    """The load-bearing case: Stripe is the source of truth.

    A card attached WITHOUT going through the CRM's save-the-default path
    (out of band, or a writeback that never landed) leaves
    ``members.stripe_payment_method_id`` NULL while the Stripe customer
    really does have a chargeable method. Answering from that column
    would report "no payment method" for a member who has one — the exact
    false negative this read exists to prevent.
    """
    member = await created.member(gym_id)
    pm_id = await created.payment_method()

    # Attach WITHOUT making it the default and WITHOUT any DB writeback.
    await payments_members_service.attach_payment_method(
        pm_id,
        member.stripe_customer_id,
        stripe_account_id,
        idempotency_key=f"pm-status-test:{member.member_id}",
    )

    # The cached column is still NULL — only Stripe knows about the card.
    assert await _read_payment_method_id(db_pool, member.member_id) is None
    assert await management_service.has_payment_method(member.member_id) is True


async def test_has_payment_method_false_despite_stale_cached_column(
    management_service,
    db_pool,
    gym_id,
    created,
):
    """The other direction: a stale non-null column can't fake a True.

    ``stripe_payment_method_id`` left pointing at a method that is no
    longer attached (a detach whose writeback lost the race) must not
    report a card the gym cannot charge.
    """
    member = await created.member(gym_id)

    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE members SET stripe_payment_method_id = :pm "
                "WHERE member_id = :id"
            ),
            {"pm": "pm_never_attached", "id": str(member.member_id)},
        )
        await session.commit()

    assert await management_service.has_payment_method(member.member_id) is False


async def test_has_payment_method_raises_when_stripe_fails(
    db_pool,
    gym_id,
    created,
):
    """A Stripe failure raises — it must never degrade to ``False``.

    The payments boundary is mocked here (a real outage can't be summoned
    on demand); everything above it is the production wiring.
    """
    member = await created.member(gym_id)

    failing_payments = MagicMock()
    failing_payments.has_attached_payment_method = AsyncMock(
        side_effect=PaymentsStripeError("Stripe is unreachable"),
    )
    service = MembersManagementService(
        db_pool,
        failing_payments,
        MagicMock(),
    )

    with pytest.raises(PaymentsStripeError):
        await service.has_payment_method(member.member_id)


async def test_has_payment_method_raises_for_unknown_member(
    management_service,
):
    """An unknown member is an error (→ 404 at the route), not a False.

    Asserted on the TYPE, not on the message: the route reads the 404 off
    ``MemberNotFoundError.status_code``, so matching prose here would lock the
    wrong half of the contract (see tests/members/test_members_error_mapping).
    """
    with pytest.raises(MemberNotFoundError):
        await management_service.has_payment_method(
            UUID("00000000-0000-0000-0000-000000000000"),
        )
