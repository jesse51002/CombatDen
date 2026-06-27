"""C-086 regression: a retried one-time start replay maps to HTTP 409.

Pure unit test (no DB / Stripe / network). When ``_crm_insert`` detects the
idempotent-replay shortfall it raises ``MembershipStartReplayError``; the start
handler must surface that as a 409 (a retryable conflict, never auto-retried),
NOT the old bare-``RuntimeError`` 500.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException, status

from src.memberships.memberships_exceptions import (
    MembershipStartReplayError,
)
from src.memberships.memberships_router import start_membership


def _make_auth() -> MagicMock:
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    return auth


def _make_request() -> MagicMock:
    request = MagicMock()
    request.memberships = [MagicMock(member_id="m1")]
    return request


@pytest.mark.asyncio
async def test_start_replay_maps_to_409() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.start = AsyncMock(
        side_effect=MembershipStartReplayError(requested=2, returned=1),
    )

    with pytest.raises(HTTPException) as exc_info:
        await start_membership(
            request=_make_request(),
            response=MagicMock(),
            credentials=MagicMock(),
            auth=auth,
            memberships_service=service,
        )

    assert exc_info.value.status_code == status.HTTP_409_CONFLICT
    # The conflict detail carries the replay explanation, not a generic 500.
    assert "replay" in str(exc_info.value.detail).lower()


@pytest.mark.asyncio
async def test_start_replay_is_not_5xx() -> None:
    """A replay is a non-auto-retried 4xx — never any 5xx."""
    auth = _make_auth()
    service = MagicMock()
    service.start = AsyncMock(
        side_effect=MembershipStartReplayError(requested=3, returned=2),
    )

    with pytest.raises(HTTPException) as exc_info:
        await start_membership(
            request=_make_request(),
            response=MagicMock(),
            credentials=MagicMock(),
            auth=auth,
            memberships_service=service,
        )

    assert exc_info.value.status_code < 500
