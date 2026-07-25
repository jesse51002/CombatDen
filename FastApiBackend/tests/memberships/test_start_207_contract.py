"""The start endpoint's 207 contract (pure unit — no DB / Stripe / network).

Two things are pinned here.

**1. What a ``failed`` result item MEANS.** A start can fail in three ways once
it has begun, and they demand different responses from the front desk, so the
reason prefix distinguishes them:

* ``card declined: …`` — the BANK refused. Nothing was collected for that
  group; offering another card is the fix.
* ``not collected: …`` — nobody refused and the money still did not arrive:
  ``invoices.pay`` RETURNED with the invoice open because the off-session
  PaymentIntent needs SCA / 3-D Secure. Nothing collected, nothing booked.
  Deliberately NOT ``declined`` — "try another card" is wrong advice when no
  bank said no. This is the outcome the kiosk path had NO answer for: the
  charge reported ``status="open"``, the writeback stamped the rows
  ``applied``, and a membership nobody paid for was booked on a 201.
* ``system failure: …`` — OUR side broke. Another card cannot help.

The change these tests lock in: a NON-card failure in the recurring converge
used to re-raise unconditionally → the router's 500, whose documented contract
is *"nothing created"*. But ``start()`` charges the one-time group FIRST and
``_verify_group(keep_unverified=True)`` deliberately KEEPS those billed rows, so
that 500 could be emitted over a collected charge and a live membership. It now
reports the truth per item (a 207 with a system-failure reason) **only** in that
case; with nothing collected it still raises, because then "nothing created" is
literally true.

**2. The route declares the 207 body.** The 207 is the primary kiosk decline
surface — a client has to read ``results[]`` to know which memberships exist —
so it carries the response ``model``, not just a description.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import stripe
from fastapi import Response, status
from schema.membership_plan import PlanType

from src.memberships.memberships_router import (
    member_memberships_router,
    start_membership,
)
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartItemState,
    MemberMembershipsStartRequest,
    MemberMembershipsStartResponse,
    MemberMembershipsStartStatus,
)
from src.memberships.service.memberships_start import (
    CARD_DECLINED_PREFIX,
    NOT_COLLECTED_PREFIX,
    SYSTEM_FAILURE_PREFIX,
    MemberMembershipsStart,
)
from src.payments.payments_exceptions import PaymentsNotCollectedError

GYM_ID = uuid4()
PAYER_ID = uuid4()


def _request(price_ids: list) -> MemberMembershipsStartRequest:
    """A real start body — one item per price (the payer buys for themselves)."""
    return MemberMembershipsStartRequest(
        payer_member_id=PAYER_ID,
        gym_id=GYM_ID,
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(member_id=PAYER_ID, price_id=price_id)
            for price_id in price_ids
        ],
    )


def _state(plan_type: PlanType) -> MemberMembershipsStartItemState:
    """One working state with an item_id already assigned (post-insert)."""
    return MemberMembershipsStartItemState(
        member_id=PAYER_ID,
        gym_id=GYM_ID,
        plan_id=uuid4(),
        plan_type=plan_type,
        item_id=uuid4(),
    )


def _build_start(
    *,
    converge_error: Exception | None = None,
    charge_error: Exception | None = None,
) -> MemberMembershipsStart:
    """The start service over doubles, with the DB-touching steps stubbed.

    ``_cleanup_states`` and ``_verify_group`` both write/read rows; what is under
    test is the FAILURE CLASSIFICATION around them, so they are AsyncMocks the
    tests assert against.
    """
    payment_sync = MagicMock()
    payment_sync.update_payments_recurring = AsyncMock(
        side_effect=converge_error,
    )
    payment_sync_one_time = MagicMock()
    payment_sync_one_time.charge_one_time = AsyncMock(side_effect=charge_error)

    start = MemberMembershipsStart(
        MagicMock(),  # db_pool
        payment_sync,
        MagicMock(),  # gym_stripe_service
        payment_sync_one_time=payment_sync_one_time,
        update_discounts=MagicMock(),
        discounts_service=MagicMock(),
        validation=MagicMock(),
        members_management_service=MagicMock(),
    )
    start._cleanup_states = AsyncMock()
    start._verify_group = AsyncMock()
    return start


def _decline() -> stripe.CardError:
    return stripe.CardError(
        "Your card was declined.",
        param=None,
        code="card_declined",
    )


# ── The three reason prefixes must stay tellable apart ──────────────


@pytest.mark.parametrize(
    ("left", "right"),
    [
        (CARD_DECLINED_PREFIX, SYSTEM_FAILURE_PREFIX),
        (CARD_DECLINED_PREFIX, NOT_COLLECTED_PREFIX),
        (NOT_COLLECTED_PREFIX, SYSTEM_FAILURE_PREFIX),
    ],
)
def test_reason_prefixes_are_mutually_exclusive(left: str, right: str) -> None:
    """No prefix may be a prefix of another, or a client that switches on
    "starts with" would classify one outcome as a different one — sending the
    member off to find another card for an outage, or telling staff a bank
    refused when none did."""
    assert left != right
    assert not left.startswith(right)
    assert not right.startswith(left)


@pytest.mark.parametrize(
    "prefix", [SYSTEM_FAILURE_PREFIX, NOT_COLLECTED_PREFIX]
)
def test_only_a_real_decline_says_declined(prefix: str) -> None:
    """Staff skim these reasons, so the word must not leak into the two
    outcomes where no bank refused."""
    assert "declin" not in prefix


# ── The recurring arm: NON-card failure after money moved → data ────


@pytest.mark.asyncio
async def test_recurring_system_failure_after_a_charge_is_data_not_a_raise() -> None:
    """A non-card failure with the one-time leg already charged is per-item DATA.

    ``start`` must NOT raise here: the router's 500 says "nothing created", and
    the one-time memberships this request charged for are live. The recurring
    items come back ``failed`` with the SYSTEM-FAILURE reason, which the front
    desk (and the kiosk) must be able to tell apart from a bank decline — the
    whole point of the distinction.
    """
    start = _build_start(converge_error=RuntimeError("stripe gateway exploded"))
    group = [_state(PlanType.recurring)]

    # Must NOT raise, even though the converge did.
    await start._converge_recurring_group(
        _request([uuid4()]), group, one_time_committed=True,
    )

    state = group[0]
    assert state.status == MemberMembershipsStartStatus.failed
    assert state.error is not None
    assert state.error.startswith(SYSTEM_FAILURE_PREFIX)
    # NOT a decline, in any wording — this is the distinction that matters. The
    # substring check is deliberate: staff skim these reasons, and a stray
    # "decline" anywhere in the prose re-creates the confusion the prefix exists
    # to prevent.
    assert not state.error.startswith(CARD_DECLINED_PREFIX)
    assert "declin" not in state.error.lower()
    # The recurring group's own un-billed rows are still cleaned up (exactly
    # once — the fail-group must not delete them a second time).
    start._cleanup_states.assert_awaited_once_with(group)


@pytest.mark.asyncio
async def test_recurring_system_failure_is_logged_when_swallowed(caplog) -> None:
    """Swallowing the exception is what would make a real outage invisible (the
    router never sees it), so it must be logged WITH the stack right here."""
    start = _build_start(converge_error=RuntimeError("stripe gateway exploded"))
    group = [_state(PlanType.recurring)]

    with caplog.at_level("ERROR"):
        await start._converge_recurring_group(
            _request([uuid4()]), group, one_time_committed=True,
        )

    assert any(
        record.levelname == "ERROR" and record.exc_info is not None
        for record in caplog.records
    ), "the swallowed system failure must be logged with its traceback"


@pytest.mark.asyncio
async def test_recurring_system_failure_with_nothing_collected_still_raises() -> None:
    """With no charge collected anywhere, a total failure is still a 500.

    "Nothing created" is literally true then, so the old behaviour stands
    untouched: propagate, and let the router answer a non-retryable 500. Only
    the after-money-moved case changed.
    """
    boom = RuntimeError("stripe gateway exploded")
    start = _build_start(converge_error=boom)
    group = [_state(PlanType.recurring)]

    with pytest.raises(RuntimeError):
        await start._converge_recurring_group(
            _request([uuid4()]), group, one_time_committed=False,
        )

    # Rows still cleaned, and no misleading `failed` reason was invented for a
    # response that is never going to be built.
    start._cleanup_states.assert_awaited_once_with(group)
    assert group[0].status == MemberMembershipsStartStatus.created


@pytest.mark.asyncio
async def test_recurring_card_decline_is_still_a_decline() -> None:
    """A real bank decline is unchanged, and never wears the system prefix."""
    start = _build_start(converge_error=_decline())
    group = [_state(PlanType.recurring)]

    await start._converge_recurring_group(
        _request([uuid4()]), group, one_time_committed=True,
    )

    state = group[0]
    assert state.status == MemberMembershipsStartStatus.failed
    assert state.error is not None
    assert state.error.startswith(CARD_DECLINED_PREFIX)
    assert not state.error.startswith(SYSTEM_FAILURE_PREFIX)


# ── The one-time arm reports whether it committed ───────────────────


@pytest.mark.asyncio
async def test_one_time_charge_reports_committed() -> None:
    """A charge that went through reports True — even when a row's writeback was
    not confirmed, because that row is KEPT (billed lines are never un-billed),
    so money has moved regardless."""
    start = _build_start()
    group = [_state(PlanType.one_time)]

    assert await start._charge_one_time_group(_request([uuid4()]), group) is True


@pytest.mark.asyncio
async def test_one_time_decline_reports_not_committed() -> None:
    """A decline collected nothing and cleaned its rows, so it reports False —
    a later recurring failure is then still an honest total failure."""
    start = _build_start(charge_error=_decline())
    group = [_state(PlanType.one_time)]

    assert (
        await start._charge_one_time_group(_request([uuid4()]), group) is False
    )
    assert group[0].error is not None
    assert group[0].error.startswith(CARD_DECLINED_PREFIX)


@pytest.mark.asyncio
async def test_one_time_non_card_failure_still_raises() -> None:
    """The one-time arm's own non-card failure is unchanged: nothing was
    collected at that point, so it propagates to a 500."""
    start = _build_start(charge_error=RuntimeError("gateway exploded"))
    group = [_state(PlanType.one_time)]

    with pytest.raises(RuntimeError):
        await start._charge_one_time_group(_request([uuid4()]), group)


# ── The third outcome: nobody refused, nothing was collected ────────


@pytest.mark.asyncio
async def test_one_time_not_collected_is_data_with_its_own_reason() -> None:
    """A ``PaymentsNotCollectedError`` is a DEFINITIVE outcome, not an outage.

    It must not raise (that would be a 500 for an ordinary business result),
    must not wear the decline prefix (no bank refused, so "try another card" is
    wrong advice), and must not wear the system-failure prefix (our side is
    fine). It reports ``False``, so a later recurring failure can still honestly
    claim nothing was collected.
    """
    start = _build_start(charge_error=PaymentsNotCollectedError("needs auth"))
    group = [_state(PlanType.one_time)]

    committed = await start._charge_one_time_group(_request([uuid4()]), group)

    assert committed is False
    state = group[0]
    assert state.status == MemberMembershipsStartStatus.failed
    assert state.error is not None
    assert state.error.startswith(NOT_COLLECTED_PREFIX)
    assert not state.error.startswith(CARD_DECLINED_PREFIX)
    assert not state.error.startswith(SYSTEM_FAILURE_PREFIX)
    assert "declin" not in state.error.lower()


@pytest.mark.asyncio
async def test_not_collected_never_books_the_membership() -> None:
    """Nothing collected ⇒ nothing booked, and nothing left looking booked.

    Two things make that true and both are asserted: the rows are cleaned up
    (they are provably un-billed — the raise happened before
    ``PaymentSyncOneTime._writeback``, so no ``stripe_item_id`` and still
    ``not_added``), and ``_verify_group`` is never reached, so its
    ``keep_unverified=True`` cannot preserve them as "billed but unconfirmed".
    """
    start = _build_start(charge_error=PaymentsNotCollectedError("needs auth"))
    group = [_state(PlanType.one_time)]

    await start._charge_one_time_group(_request([uuid4()]), group)

    start._cleanup_states.assert_awaited_once_with(group)
    start._verify_group.assert_not_awaited()


@pytest.mark.asyncio
async def test_start_returns_207_for_a_non_collecting_charge() -> None:
    """End of the chain: the router answers 207, never 201 and never 500.

    The whole path runs for real here — the payment layer's
    ``PaymentsNotCollectedError`` goes through ``start()`` into the response
    breakdown and out through the actual route handler — because every link is
    where this used to silently succeed.
    """
    price_id = uuid4()
    request = _request([price_id])

    start = _build_start(charge_error=PaymentsNotCollectedError("needs auth"))
    start._insert_all = AsyncMock()
    start._validation.validate = AsyncMock(
        return_value=(
            MagicMock(timezone="America/Chicago"),
            {price_id: {"plan_id": uuid4(), "plan_type": PlanType.one_time.value}},
        ),
    )

    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    service = MagicMock()
    service.start = start.start
    response = Response()

    result = await start_membership(
        request=request,
        response=response,
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    assert response.status_code == status.HTTP_207_MULTI_STATUS
    assert len(result.results) == 1
    item = result.results[0]
    assert item.status == MemberMembershipsStartStatus.failed
    # No membership id is handed back — nothing was created.
    assert item.item_id is None
    assert item.error is not None and item.error.startswith(NOT_COLLECTED_PREFIX)


# ── start() threads the answer from one arm to the other ────────────


@pytest.mark.asyncio
async def test_start_tells_the_recurring_arm_that_the_one_time_leg_charged() -> None:
    """The wiring: whatever the one-time arm reports is what the recurring arm
    is told. A hardcoded ``False`` here would silently restore the old 500."""
    one_time_price, recurring_price = uuid4(), uuid4()
    request = _request([one_time_price, recurring_price])

    start = _build_start()
    start._insert_all = AsyncMock()
    start._charge_one_time_group = AsyncMock(return_value=True)
    start._converge_recurring_group = AsyncMock()
    start._validation.validate = AsyncMock(
        return_value=(
            MagicMock(timezone="America/Chicago"),
            {
                one_time_price: {
                    "plan_id": uuid4(),
                    "plan_type": PlanType.one_time.value,
                },
                recurring_price: {
                    "plan_id": uuid4(),
                    "plan_type": PlanType.recurring.value,
                },
            },
        ),
    )

    result = await start.start(request)

    assert (
        start._converge_recurring_group.await_args.kwargs["one_time_committed"]
        is True
    )
    # Mixed cart → two charges, and the client is told so.
    assert result.charge_count == 2
    assert result.multiple_charges is True


# ── The route declares the 207 BODY, not just a description ─────────


def test_start_route_207_declares_the_breakdown_model() -> None:
    """A client generator must see the per-item breakdown on the 207, exactly as
    retry-card's 207 declares its decline body — this route is the primary kiosk
    decline surface, so a description alone leaves the generated client blind."""
    route = next(
        r
        for r in member_memberships_router.routes
        if r.path == "/api/v1/member_memberships/" and "POST" in r.methods
    )

    assert route.responses[207]["model"] is MemberMembershipsStartResponse
    # The 500 must no longer claim "nothing created" unconditionally — a failure
    # after money moved is the 207 above.
    assert "nothing charged" in route.responses[500]["description"]
