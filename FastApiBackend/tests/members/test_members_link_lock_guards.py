"""A busy payer lock on the authorized-payer routes is a 409, not a 500.

Pure unit tests (no DB / Stripe / network). The mirror of
``tests/memberships/test_billing_endpoint_guards.py``'s C-075 section, for the
three ``/link*`` handlers in ``src/members/members_router.py`` — the same hazard
in a different router, so the same shape of proof.

**Two halves, and the second is the one that bites.** The global handler in
``src/main.py`` (``_handle_lock_busy_error``) maps ``LockBusyError`` to 409 and
always did. But every one of these handlers wraps its service call in
``try/except Exception -> 500``, the lock is acquired INSIDE the service (so the
error is raised within that ``try``), and ``LockBusyError`` subclasses
``Exception`` **directly** — so without a typed arm that re-raises, the generic
arm swallows the error and the global handler can never fire. Front desk
authorizing a payer while a bulk reprice holds either account's lock then got an
opaque 500 "Failed to link member" for a perfectly retryable conflict, and
transient contention was indistinguishable from an outage.

The fix is `except LockBusyError: raise` above the generic arm — a ``raise``
inside an ``except`` clause propagates out of the WHOLE ``try``, so the sibling
``except Exception`` cannot re-catch it. These tests are what prove it: a
swallowed error surfaces as ``HTTPException(500)`` instead of the
``LockBusyError`` asserted here.

``POST /members/{id}/link/check`` is deliberately ABSENT from the table below:
``check_link_account`` is a pure read that takes no lock, so an arm there would
be dead code that reads as coverage.
"""

import inspect
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.main import _handle_lock_busy_error
from src.members.members_router import (
    link_member_account,
    preview_remove_authorization,
    remove_authorization,
)
from src.shared.paying_member_lock import LockBusyError

# Each authorized-payer handler whose service takes ``PayingMemberLock``, paired
# with the facade method that takes it:
#   * link_account            -> locks [member, payer] inside
#                                MemberMembershipsLinked
#   * preview_remove_authorization -> locks [payer] in the facade (a READ, but
#                                the figures it quotes must not be computed
#                                mid-converge)
#   * remove_authorization    -> locks [member, payer] itself
_LOCKING_HANDLERS = [
    (link_member_account, "link_account"),
    (preview_remove_authorization, "preview_remove_authorization"),
    (remove_authorization, "remove_authorization"),
]


def _make_auth() -> MagicMock:
    """An auth double that admits the caller through either member gate."""
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    # The link handler resolves the operator/witness through this gate instead.
    auth.get_employee_id_for_member = AsyncMock(return_value=uuid4())
    return auth


def _make_http_request() -> MagicMock:
    """A request double the signing-audit capture can read.

    ``capture_ip_address`` / ``capture_user_agent`` run BEFORE the service call
    on the link path, so they must return real values rather than raise — a
    ``MagicMock`` header lookup would hand a mock into the service, which is
    harmless here but noisy to debug if the assertion ever fails.
    """
    http_request = MagicMock()
    http_request.client = MagicMock(host="203.0.113.7")
    http_request.headers = {"user-agent": "pytest-agent"}
    return http_request


def _handler_kwargs(handler, service: MagicMock) -> dict:
    """Build the doubles each handler's signature actually asks for."""
    available = {
        "member_id": uuid4(),
        "request": MagicMock(payer_member_id=uuid4()),
        "http_request": _make_http_request(),
        "credentials": MagicMock(),
        "auth": _make_auth(),
        "memberships_service": service,
    }
    params = inspect.signature(handler).parameters
    return {k: v for k, v in available.items() if k in params}


@pytest.mark.parametrize(
    ("handler", "method"),
    _LOCKING_HANDLERS,
    ids=[handler.__name__ for handler, _ in _LOCKING_HANDLERS],
)
@pytest.mark.asyncio
async def test_lock_busy_error_propagates_out_of_locking_handler(
    handler,
    method: str,
) -> None:
    """A busy payer must ESCAPE the handler so the global 409 handler sees it."""
    service = MagicMock()
    setattr(
        service,
        method,
        AsyncMock(side_effect=LockBusyError("payer:abc")),
    )

    with pytest.raises(LockBusyError):
        await handler(**_handler_kwargs(handler, service))


@pytest.mark.asyncio
async def test_propagated_lock_busy_error_becomes_a_409_body() -> None:
    """End-to-end of the two halves: what escapes a handler is what the global
    handler formats — a 409 with a plain-string ``detail``, never a 500.

    Driven through the authorize-payer write because that is the call staff
    actually make while another billing op may hold a lock.
    """
    service = MagicMock()
    service.link_account = AsyncMock(side_effect=LockBusyError("payer:abc"))

    with pytest.raises(LockBusyError) as caught:
        await link_member_account(
            **_handler_kwargs(link_member_account, service)
        )

    response = await _handle_lock_busy_error(MagicMock(), caught.value)
    assert response.status_code == 409
    assert b"payer:abc" in response.body


@pytest.mark.asyncio
async def test_link_check_takes_no_lock_so_has_no_arm() -> None:
    """``check_link_account`` really does take no lock — the reason
    ``POST /link/check`` is absent from the table above.

    Asserted against the SOURCE of the service method rather than left as a
    comment: if a future change wraps that read in the payer lock, this fails
    and points at the handler that then needs the re-raise arm. A dead
    ``except LockBusyError`` on a non-locking handler is worse than none (it
    reads as coverage), so the exclusion has to be checkable.
    """
    from src.memberships.service.memberships_linked import (
        MemberMembershipsLinked,
    )

    source = inspect.getsource(MemberMembershipsLinked.check_link_account)
    assert "_paying_lock" not in source
