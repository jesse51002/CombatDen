"""Smoke + edge tests for the checkin router.

The gated check-in flow runs many DB queries plus the cycle-counts service, so
these router tests override the resolver + member-gate providers with doubles
and assert the router's wiring (auth -> resolve -> gate -> serialization). The
gating *logic* is unit-tested directly in
``checkin/test_checkin_plan_selector.py``.
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinItemResult,
    BatchCheckinItemStatus,
    BatchCheckinResponse,
)
from src.checkin.schema.checkin_schema import (
    AttendeeListResponse,
    CheckinMembershipBreakdown,
    CheckinResponse,
    CheckinWarning,
)
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupResponse,
)
from src.main import app

_STUB_STREAK_WEEKS = 3


def _override_checkin(response: CheckinResponse) -> None:
    """Double the resolver + member gate + streak service so the single-checkin
    handler returns ``response`` (enriched with a stub streak) without touching
    the DB. Caller resets via ``_reset_checkin``.
    """
    resolver = MagicMock()
    resolver.resolve = AsyncMock(return_value=MagicMock())
    gate = MagicMock()
    gate.checkin_member = AsyncMock(return_value=response)
    streak = MagicMock()
    streak.get_streak = AsyncMock(return_value=_STUB_STREAK_WEEKS)
    app.container.checkin_class_resolver.override(resolver)
    app.container.checkin_member_gate.override(gate)
    app.container.streak_service.override(streak)


def _reset_checkin() -> None:
    """Undo the ``_override_checkin`` provider overrides."""
    app.container.checkin_class_resolver.reset_override()
    app.container.checkin_member_gate.reset_override()
    app.container.streak_service.reset_override()


def test_checkin_records_when_a_plan_covers_the_class(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A covered check-in returns the log_id, chosen plan/item, points, and
    breakdown."""
    log_id = str(uuid4())
    plan_id = uuid4()
    item_id = uuid4()
    class_id = str(uuid4())

    response = CheckinResponse(
        log_id=log_id,
        member_id=fake_member_id,
        class_id=class_id,
        already_checked_in=False,
        chosen_plan_id=plan_id,
        chosen_item_id=item_id,
        points_awarded=50,
        memberships=[
            CheckinMembershipBreakdown(
                item_id=item_id,
                plan_id=plan_id,
                plan_type="recurring",
                class_count=None,
                classes_used=4,
                classes_remaining=None,
                is_eligible=True,
                renew_date=date(2026, 7, 1),
                end_date=None,
            )
        ],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": class_id,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        _reset_checkin()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] == log_id
    assert body["already_checked_in"] is False
    # A recorded check-in folds in the member's streak.
    assert body["class_streak_weeks"] == _STUB_STREAK_WEEKS
    assert body["chosen_plan_id"] == str(plan_id)
    assert body["chosen_item_id"] == str(item_id)
    assert body["points_awarded"] == 50
    assert body["memberships"][0]["is_eligible"] is True


def test_checkin_idempotent_repeat_also_folds_in_the_streak(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """An already-checked-in repeat is a real attendance too: the gate's
    repeat builder leaves ``class_streak_weeks`` at 0, and it is the ROUTER
    that folds the streak into the response — for repeats exactly like fresh
    check-ins (the fold condition is ``log_id is not None OR
    already_checked_in``)."""
    class_id = str(uuid4())
    response = CheckinResponse(
        log_id=str(uuid4()),
        member_id=fake_member_id,
        class_id=class_id,
        already_checked_in=True,
        chosen_plan_id=None,
        chosen_item_id=None,
        points_awarded=50,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": class_id,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        _reset_checkin()

    assert resp.status_code == 200
    body = resp.json()
    assert body["already_checked_in"] is True
    assert body["class_streak_weeks"] == _STUB_STREAK_WEEKS


def test_checkin_rejected_when_no_plan_covers(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A kiosk-gate rejection returns 200 with null log_id, no chosen plan, a
    skip_reason, and 0 points."""
    class_id = str(uuid4())
    response = CheckinResponse(
        log_id=None,
        member_id=fake_member_id,
        class_id=class_id,
        already_checked_in=False,
        chosen_plan_id=None,
        chosen_item_id=None,
        points_awarded=0,
        skip_reason=CheckinWarning.ineligible_plan,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": class_id,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "is_member": True,
            },
            headers=auth_headers,
        )
    finally:
        _reset_checkin()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] is None
    assert body["chosen_plan_id"] is None
    assert body["chosen_item_id"] is None
    assert body["already_checked_in"] is False
    assert body["points_awarded"] == 0
    assert body["skip_reason"] == "ineligible_plan"


def test_checkin_staff_needs_confirmation(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A staff (is_member=False) check-in the gate warns on, without an override,
    is held for confirmation: 200, log_id null, requires_confirmation true, the
    warning, nothing written."""
    class_id = str(uuid4())
    response = CheckinResponse(
        log_id=None,
        member_id=fake_member_id,
        class_id=class_id,
        already_checked_in=False,
        chosen_plan_id=None,
        chosen_item_id=None,
        points_awarded=0,
        skip_reason=None,
        warnings=[CheckinWarning.no_membership],
        requires_confirmation=True,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": class_id,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        _reset_checkin()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] is None
    assert body["requires_confirmation"] is True
    # Not recorded -> no streak fetched, stays 0.
    assert body["class_streak_weeks"] == 0
    assert body["chosen_plan_id"] is None
    assert body["skip_reason"] is None
    assert body["warnings"] == ["no_membership"]
    assert body["points_awarded"] == 0


def test_checkin_idempotent_returns_already_checked_in(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A duplicate check-in returns the existing log_id with already_checked_in=True."""
    log_id = str(uuid4())
    plan_id = uuid4()
    item_id = uuid4()
    class_id = str(uuid4())

    response = CheckinResponse(
        log_id=log_id,
        member_id=fake_member_id,
        class_id=class_id,
        already_checked_in=True,
        chosen_plan_id=plan_id,
        chosen_item_id=item_id,
        points_awarded=0,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": class_id,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        _reset_checkin()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] == log_id
    assert body["already_checked_in"] is True
    # A repeat still folds in the current streak.
    assert body["class_streak_weeks"] == _STUB_STREAK_WEEKS
    assert body["points_awarded"] == 0


# ---------------------------------------------------------------------------
# POST /api/v1/checkin/batch
#
# class_id + occurrence_date now ride in the body (not the path). The batch
# service is overridden with a double; these assert the router's status-code
# mapping (207 on any processed mix, 500 on total failure, 404/400 on an
# unresolved occurrence, 422 on an empty member list) + serialization. The batch
# FLOW is unit-tested in checkin/test_batch_checkin_service.py.
# ---------------------------------------------------------------------------

_BATCH_CLASS_ID = uuid4()
_BATCH_OCCURRENCE_DATE = "2026-06-01"
_BATCH_OCCURRENCE_TIME = "17:00:00"
_BATCH_URL = "/api/v1/checkin/batch"


def _batch_body(gym_id, member_ids: list[str]) -> dict:
    """A batch request body with class_id + occurrence_date/time in the body."""
    return {
        "gym_id": gym_id,
        "class_id": str(_BATCH_CLASS_ID),
        "occurrence_date": _BATCH_OCCURRENCE_DATE,
        "occurrence_time": _BATCH_OCCURRENCE_TIME,
        "member_ids": member_ids,
    }


def _override_batch(*, return_value=None, side_effect=None):
    """Override the batch service double; caller resets the override."""
    service = MagicMock()
    service.batch_checkin = AsyncMock(
        return_value=return_value, side_effect=side_effect
    )
    app.container.batch_checkin_service.override(service)
    return service


def test_batch_checkin_returns_207_with_per_member_results(
    client, auth_headers, fake_gym_id
):
    """A mix of checked_in / already_checked_in / skipped returns 207 with the
    per-member split."""
    m1, m2, m3 = uuid4(), uuid4(), uuid4()
    response = BatchCheckinResponse(
        class_id=_BATCH_CLASS_ID,
        occurrence_date=date(2026, 6, 1),
        results=[
            BatchCheckinItemResult(
                member_id=m1,
                status=BatchCheckinItemStatus.checked_in,
                points_awarded=50,
                chosen_plan_id=uuid4(),
                chosen_item_id=uuid4(),
                log_id=uuid4(),
            ),
            BatchCheckinItemResult(
                member_id=m2,
                status=BatchCheckinItemStatus.already_checked_in,
                chosen_plan_id=uuid4(),
                chosen_item_id=uuid4(),
                log_id=uuid4(),
            ),
            BatchCheckinItemResult(
                member_id=m3,
                status=BatchCheckinItemStatus.skipped,
                reason="no_membership",
            ),
        ],
    )
    _override_batch(return_value=(response, False))
    try:
        resp = client.post(
            _BATCH_URL,
            json=_batch_body(fake_gym_id, [str(m1), str(m2), str(m3)]),
            headers=auth_headers,
        )
    finally:
        app.container.batch_checkin_service.reset_override()

    assert resp.status_code == 207
    body = resp.json()
    assert [r["status"] for r in body["results"]] == [
        "checked_in",
        "already_checked_in",
        "skipped",
    ]
    assert body["results"][2]["reason"] == "no_membership"


def test_batch_checkin_total_failure_returns_500(
    client, auth_headers, fake_gym_id
):
    """When every member failed (all_failed True) the router returns 500, not
    207 — a total failure must not look like a partial success."""
    m1 = uuid4()
    response = BatchCheckinResponse(
        class_id=_BATCH_CLASS_ID,
        occurrence_date=date(2026, 6, 1),
        results=[
            BatchCheckinItemResult(
                member_id=m1,
                status=BatchCheckinItemStatus.failed,
                reason="db down",
            ),
        ],
    )
    _override_batch(return_value=(response, True))
    try:
        resp = client.post(
            _BATCH_URL,
            json=_batch_body(fake_gym_id, [str(m1)]),
            headers=auth_headers,
        )
    finally:
        app.container.batch_checkin_service.reset_override()

    assert resp.status_code == 500


def test_batch_checkin_class_not_found_returns_404(
    client, auth_headers, fake_gym_id
):
    """A ValueError mentioning 'not found' maps to 404 before any member work."""
    _override_batch(side_effect=ValueError("Class not found"))
    try:
        resp = client.post(
            _BATCH_URL,
            json=_batch_body(fake_gym_id, [str(uuid4())]),
            headers=auth_headers,
        )
    finally:
        app.container.batch_checkin_service.reset_override()

    assert resp.status_code == 404


def test_batch_checkin_invalid_occurrence_returns_400(
    client, auth_headers, fake_gym_id
):
    """A non-'not found' ValueError (not a real occurrence) maps to 400."""
    _override_batch(
        side_effect=ValueError(
            "No class occurrence on 2026-06-01 for this class"
        )
    )
    try:
        resp = client.post(
            _BATCH_URL,
            json=_batch_body(fake_gym_id, [str(uuid4())]),
            headers=auth_headers,
        )
    finally:
        app.container.batch_checkin_service.reset_override()

    assert resp.status_code == 400


def test_batch_checkin_empty_member_ids_returns_422(
    client, auth_headers, fake_gym_id
):
    """An empty member list violates min_length=1 -> 422 (no service call)."""
    resp = client.post(
        _BATCH_URL,
        json=_batch_body(fake_gym_id, []),
        headers=auth_headers,
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/v1/signup, DELETE /api/v1/signup
# ---------------------------------------------------------------------------


def _signup_body(gym_id: str, member_id: str, class_id: str) -> dict:
    return {
        "member_id": member_id,
        "gym_id": gym_id,
        "class_id": class_id,
        "occurrence_date": "2026-06-01",
        "occurrence_time": "17:00:00",
    }


def test_signup_creates_and_returns_id(client, auth_headers, fake_gym_id):
    """A fresh sign-up returns 200 with already_signed_up=False."""
    signup_id = uuid4()
    service = MagicMock()
    service.create = AsyncMock(
        return_value=SignupResponse(signup_id=signup_id, already_signed_up=False)
    )
    app.container.signup_service.override(service)
    try:
        resp = client.post(
            "/api/v1/signup",
            json=_signup_body(fake_gym_id, str(uuid4()), str(uuid4())),
            headers=auth_headers,
        )
    finally:
        app.container.signup_service.reset_override()

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["signup_id"] == str(signup_id)
    assert body["already_signed_up"] is False


def test_signup_idempotent_repeat_returns_existing_id(
    client, auth_headers, fake_gym_id
):
    """A repeat sign-up returns the existing signup_id, already_signed_up=True."""
    signup_id = uuid4()
    service = MagicMock()
    service.create = AsyncMock(
        return_value=SignupResponse(signup_id=signup_id, already_signed_up=True)
    )
    app.container.signup_service.override(service)
    try:
        resp = client.post(
            "/api/v1/signup",
            json=_signup_body(fake_gym_id, str(uuid4()), str(uuid4())),
            headers=auth_headers,
        )
    finally:
        app.container.signup_service.reset_override()

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["signup_id"] == str(signup_id)
    assert body["already_signed_up"] is True


def test_signup_full_class_returns_400(client, auth_headers, fake_gym_id):
    """A ValueError('Class is full') from the service maps to 400."""
    service = MagicMock()
    service.create = AsyncMock(side_effect=ValueError("Class is full"))
    app.container.signup_service.override(service)
    try:
        resp = client.post(
            "/api/v1/signup",
            json=_signup_body(fake_gym_id, str(uuid4()), str(uuid4())),
            headers=auth_headers,
        )
    finally:
        app.container.signup_service.reset_override()

    assert resp.status_code == 400, resp.text
    assert "full" in resp.json()["detail"].lower()


def test_signup_unknown_class_returns_404(client, auth_headers, fake_gym_id):
    """A ValueError('Class not found') from the service maps to 404."""
    service = MagicMock()
    service.create = AsyncMock(side_effect=ValueError("Class not found"))
    app.container.signup_service.override(service)
    try:
        resp = client.post(
            "/api/v1/signup",
            json=_signup_body(fake_gym_id, str(uuid4()), str(uuid4())),
            headers=auth_headers,
        )
    finally:
        app.container.signup_service.reset_override()

    assert resp.status_code == 404, resp.text


def test_signup_missing_body_returns_422(client, auth_headers) -> None:
    resp = client.post("/api/v1/signup", headers=auth_headers)
    assert resp.status_code == 422


def test_remove_signup_returns_removed_true(client, auth_headers, fake_gym_id):
    service = MagicMock()
    service.remove = AsyncMock(return_value=SignupRemoveResponse(removed=True))
    app.container.signup_service.override(service)
    try:
        resp = client.request(
            "DELETE",
            "/api/v1/signup",
            params={
                "member_id": str(uuid4()),
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.signup_service.reset_override()

    assert resp.status_code == 200, resp.text
    assert resp.json()["removed"] is True


def test_remove_signup_missing_params_returns_422(client, auth_headers) -> None:
    resp = client.request("DELETE", "/api/v1/signup", headers=auth_headers)
    assert resp.status_code == 422


def test_attendees_returns_list(client, auth_headers, fake_gym_id):
    """GET /api/v1/checkin/attendees returns the combined roster: an attended
    member (with billing attribution) and a signed-up-only member (attendance
    fields null)."""
    class_id = uuid4()
    member_a, member_b = uuid4(), uuid4()
    plan_id, item_id = uuid4(), uuid4()
    response = AttendeeListResponse(
        class_id=class_id,
        occurrence_date=date(2026, 6, 1),
        attendees=[
            {
                "member_id": member_a,
                "full_name": "Aaron Ant",
                "signed_up": True,
                "attended": True,
                "log_id": uuid4(),
                "plan_id": plan_id,
                "item_id": item_id,
            },
            {
                "member_id": member_b,
                "full_name": "Bea Bee",
                "signed_up": True,
                "attended": False,
                "log_id": None,
                "plan_id": None,
                "item_id": None,
            },
        ],
    )
    service = MagicMock()
    service.list_attendees = AsyncMock(return_value=response)
    app.container.checkin_attendees_service.override(service)
    try:
        resp = client.get(
            "/api/v1/checkin/attendees",
            params={
                "gym_id": fake_gym_id,
                "class_id": str(class_id),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_attendees_service.reset_override()

    assert resp.status_code == 200
    body = resp.json()
    assert len(body["attendees"]) == 2
    assert body["attendees"][0]["full_name"] == "Aaron Ant"
    assert body["attendees"][0]["signed_up"] is True
    assert body["attendees"][0]["attended"] is True
    assert body["attendees"][1]["signed_up"] is True
    assert body["attendees"][1]["attended"] is False
    assert body["attendees"][1]["log_id"] is None
    assert body["attendees"][1]["plan_id"] is None
    assert body["attendees"][1]["item_id"] is None


def test_attendees_missing_params_returns_422(client, auth_headers, fake_gym_id):
    """Omitting class_id / occurrence_date violates the query contract -> 422."""
    resp = client.get(
        "/api/v1/checkin/attendees",
        params={"gym_id": fake_gym_id},
        headers=auth_headers,
    )
    assert resp.status_code == 422


def test_streak_returns_zero_when_no_attendance(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """GET /api/v1/streak returns 0 weeks for a never-attended member."""
    streak_result = MagicMock()
    streak_result.all.return_value = []
    # Same mocked result serves both the gym-timezone lookup
    # (``scalar_one``) and the week-bucket query (``all``).
    streak_result.scalar_one.return_value = "America/Chicago"

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=streak_result)

    response = client.get(
        f"/api/v1/streak?member_id={fake_member_id}&gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["class_streak_weeks"] == 0
