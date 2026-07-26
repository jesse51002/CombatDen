"""Unit tests for the emails router (/api/v1/emails).

Mocks at the same seam as the other router tests: the ``client`` fixture
(auth + db_pool overridden) plus per-provider overrides on
``app.container`` so no DB is touched and no message is ever handed to
Resend.

Two endpoints with very different contracts live here. ``POST /send`` is
staff-only and capped per subject; ``GET /unsubscribe`` is PUBLIC by
necessity (it is opened from a mail client with no session), which is why
its failure answer is deliberately indistinguishable from its success one.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest

import src.emails.emails_router as emails_router_module
from src.emails.emails_router import RESEND_WINDOW_SECONDS
from src.emails.schema.emails_schema import InviteOutcome
from src.emails.service.emails_log import EmailsLog
from src.emails.service.emails_runner import EmailsRunner
from src.emails.service.emails_service import EmailsService
from src.emails.service.emails_suppression import EmailsSuppression
from src.main import app

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind, EmailSuppressionScope  # isort: skip

SEND_URL = "/api/v1/emails/send"
UNSUBSCRIBE_URL = "/api/v1/emails/unsubscribe"

# Comfortably above every count a test drives, so only the test that means
# to hit the cap hits it.
DEFAULT_TEST_CAP = 3


@pytest.fixture
def emails_service_mock():
    """Override the DI-wired ``EmailsService`` so no row is ever claimed."""
    service = MagicMock(spec=EmailsService)
    app.container.emails_service.override(service)
    try:
        yield service
    finally:
        app.container.emails_service.reset_override()


@pytest.fixture
def emails_log_mock():
    """Override ``EmailsLog``. Two DIFFERENT counts, on purpose.

    ``count_recent_for_subject`` (a trailing window) backs the cap and must
    reset; ``count_total_for_subject`` (all time) is the resend sequence and
    must never reset. Both are defaulted here so a test that cares sets only
    the one it is actually about.
    """
    log = MagicMock(spec=EmailsLog)
    log.count_recent_for_subject = AsyncMock(return_value=0)
    log.count_total_for_subject = AsyncMock(return_value=0)
    app.container.emails_log.override(log)
    try:
        yield log
    finally:
        app.container.emails_log.reset_override()


@pytest.fixture
def emails_runner_mock():
    """Override the DI-wired ``EmailsRunner`` so no real send is fired."""
    runner = MagicMock(spec=EmailsRunner)
    app.container.emails_runner.override(runner)
    try:
        yield runner
    finally:
        app.container.emails_runner.reset_override()


@pytest.fixture
def emails_suppression_mock():
    """Override ``EmailsSuppression`` — token verification and the write."""
    suppression = MagicMock(spec=EmailsSuppression)
    suppression.verify_token = MagicMock(return_value=None)
    suppression.suppress = AsyncMock(return_value=None)
    app.container.emails_suppression.override(suppression)
    try:
        yield suppression
    finally:
        app.container.emails_suppression.reset_override()


@pytest.fixture
def resend_cap():
    """Set the injected per-subject hourly cap for one test.

    The cap is a ``Settings``-backed provider precisely so it can be tuned
    without a deploy, so the 429 is driven through the provider rather than
    by faking a hundred rows.
    """

    def _set(cap: int) -> None:
        app.container.emails_resend_cap.override(cap)

    _set(DEFAULT_TEST_CAP)
    try:
        yield _set
    finally:
        app.container.emails_resend_cap.reset_override()


def _send_body(
    gym_id: str,
    *,
    kind: EmailKind = EmailKind.staff_onboarding,
    employee_id: str | None = None,
    member_id: str | None = None,
) -> dict:
    return {
        "gym_id": gym_id,
        "kind": str(kind),
        "employee_id": employee_id,
        "member_id": member_id,
    }


# ── POST /send ────────────────────────────────────────────────────


def test_send_returns_202_and_fires_the_runner_once(
    client,
    auth_headers,
    auth_mock,
    emails_service_mock,
    emails_log_mock,
    emails_runner_mock,
    resend_cap,
    fake_gym_id,
    fake_employee_id,
):
    """202 with the honest outcome, and exactly one detached delivery.

    The runner is fired by the ROUTER after the claim returned an id — the
    send is never inside the request, and never fires for a claim that did
    not happen.
    """
    email_id = uuid4()
    emails_service_mock.request_send = AsyncMock(
        return_value=(email_id, InviteOutcome.queued)
    )

    resp = client.post(
        SEND_URL,
        json=_send_body(fake_gym_id, employee_id=fake_employee_id),
        headers=auth_headers,
    )

    assert resp.status_code == 202, resp.text
    assert resp.json() == {
        "outcome": InviteOutcome.queued.value,
        "email_id": str(email_id),
    }
    emails_runner_mock.start.assert_called_once_with(email_id)
    auth_mock.verify_roles.assert_awaited()
    emails_log_mock.count_recent_for_subject.assert_awaited_once_with(
        UUID(fake_employee_id),
        EmailKind.staff_onboarding,
        RESEND_WINDOW_SECONDS,
    )


def test_a_kind_outside_the_manual_allowlist_is_400(
    client,
    auth_headers,
    emails_service_mock,
    emails_log_mock,
    emails_runner_mock,
    resend_cap,
    monkeypatch,
    fake_gym_id,
    fake_member_id,
):
    """A kind is automatic-only until someone allowlists it deliberately.

    Both shipped kinds are currently on the allowlist, so the guard is
    exercised by narrowing it — the alternative (asserting nothing) would
    leave the check untested until the day a new automatic-only kind ships.
    """
    monkeypatch.setattr(
        emails_router_module,
        "MANUAL_SEND_KINDS",
        frozenset({EmailKind.staff_onboarding}),
    )
    # A claimable return value on purpose: without the guard this request
    # would answer 202, so the 400 below can only come from the allowlist.
    emails_service_mock.request_send = AsyncMock(
        return_value=(uuid4(), InviteOutcome.queued)
    )

    resp = client.post(
        SEND_URL,
        json=_send_body(
            fake_gym_id,
            kind=EmailKind.member_app_invite,
            member_id=fake_member_id,
        ),
        headers=auth_headers,
    )

    assert resp.status_code == 400, resp.text
    emails_service_mock.request_send.assert_not_awaited()
    emails_runner_mock.start.assert_not_called()


def test_over_the_per_subject_hourly_cap_is_429(
    client,
    auth_headers,
    emails_service_mock,
    emails_log_mock,
    emails_runner_mock,
    resend_cap,
    fake_gym_id,
    fake_employee_id,
):
    """The cap stops one staff member turning the button into a mail bomb.

    It is our sending reputation at stake, not just that gym's, so nothing
    is claimed once the trailing-hour count reaches the injected cap.
    """
    resend_cap(1)
    emails_log_mock.count_recent_for_subject = AsyncMock(return_value=1)
    # Claimable on purpose: under the cap this request would answer 202, so
    # the 429 below can only come from the cap itself.
    emails_service_mock.request_send = AsyncMock(
        return_value=(uuid4(), InviteOutcome.queued)
    )

    resp = client.post(
        SEND_URL,
        json=_send_body(fake_gym_id, employee_id=fake_employee_id),
        headers=auth_headers,
    )

    assert resp.status_code == 429, resp.text
    emails_service_mock.request_send.assert_not_awaited()
    emails_runner_mock.start.assert_not_called()


def test_the_all_time_count_becomes_the_resend_seq(
    client,
    auth_headers,
    emails_service_mock,
    emails_log_mock,
    emails_runner_mock,
    resend_cap,
    fake_gym_id,
    fake_employee_id,
):
    """A resend must be a genuinely NEW claim, not an idempotent no-op.

    The idempotency key ends in ``resend_seq``; reusing 0 for every manual
    send would collide with the original claim, return no row, and report
    "already requested" to a staff member who is standing there because the
    first one never arrived.
    """
    resend_cap(5)
    emails_log_mock.count_recent_for_subject = AsyncMock(return_value=2)
    emails_log_mock.count_total_for_subject = AsyncMock(return_value=2)
    emails_service_mock.request_send = AsyncMock(
        return_value=(uuid4(), InviteOutcome.queued)
    )

    resp = client.post(
        SEND_URL,
        json=_send_body(fake_gym_id, employee_id=fake_employee_id),
        headers=auth_headers,
    )

    assert resp.status_code == 202, resp.text
    payload = emails_service_mock.request_send.await_args.args[0]
    assert payload.resend_seq == 2
    assert payload.employee_id == UUID(fake_employee_id)
    assert payload.gym_id == UUID(fake_gym_id)


def test_the_sequence_does_not_reset_when_the_cap_window_does(
    client,
    auth_headers,
    emails_service_mock,
    emails_log_mock,
    emails_runner_mock,
    resend_cap,
    fake_gym_id,
    fake_employee_id,
):
    """The sequence comes from the ALL-TIME count, never the cap's window.

    Regression guard. The two counts answer different questions and only one
    may reset: the cap asks "how many in the last hour" and must reset, or a
    person could never be resent to again; the sequence asks "which send is
    this" and must NEVER reset.

    Driving both from the window meant a resend more than an hour after the
    original — the normal case, since "they never got it" reaches staff hours
    or days later — recomputed seq 0, collided with the original claim's
    idempotency key, hit ON CONFLICT DO NOTHING, and answered 202 having sent
    absolutely nothing.
    """
    resend_cap(3)
    # An hour has passed: the window is empty again, but three sends have
    # happened over this person's lifetime.
    emails_log_mock.count_recent_for_subject = AsyncMock(return_value=0)
    emails_log_mock.count_total_for_subject = AsyncMock(return_value=3)
    emails_service_mock.request_send = AsyncMock(
        return_value=(uuid4(), InviteOutcome.queued)
    )

    resp = client.post(
        SEND_URL,
        json=_send_body(fake_gym_id, employee_id=fake_employee_id),
        headers=auth_headers,
    )

    assert resp.status_code == 202, resp.text
    payload = emails_service_mock.request_send.await_args.args[0]
    # 3, not 0 — a fresh key, so the claim actually lands.
    assert payload.resend_seq == 3


# ── GET /unsubscribe ──────────────────────────────────────────────


def test_an_invalid_unsubscribe_token_is_200_and_writes_nothing(
    client, emails_suppression_mock
):
    """Every failure mode answers identically, so a prober learns nothing.

    A 4xx here would also be read by a mail client's link scanner as a
    broken link, and the page is meant for a human either way.
    """
    emails_suppression_mock.verify_token = MagicMock(return_value=None)

    resp = client.get(UNSUBSCRIBE_URL, params={"token": "not-a-real-token"})

    assert resp.status_code == 200, resp.text
    emails_suppression_mock.suppress.assert_not_awaited()


def test_a_valid_token_writes_a_marketing_suppression(
    client, emails_suppression_mock
):
    """``marketing`` scope, never ``all``.

    Unsubscribing from a pitch must not cost someone the transactional mail
    that carries their access to the product.
    """
    gym_id = uuid4()
    emails_suppression_mock.verify_token = MagicMock(
        return_value=("ada@example.com", gym_id)
    )

    resp = client.get(UNSUBSCRIBE_URL, params={"token": "a-valid-token"})

    assert resp.status_code == 200, resp.text
    emails_suppression_mock.suppress.assert_awaited_once()
    args = emails_suppression_mock.suppress.await_args.args
    assert args[0] == "ada@example.com"
    assert args[1] == gym_id
    assert args[2] is EmailSuppressionScope.marketing
