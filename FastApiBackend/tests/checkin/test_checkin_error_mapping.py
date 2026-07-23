"""The check-in domain's exception TYPE -> (HTTP status, ``code``) contract.

This is the regression the router could not previously catch. The status used
to be picked with ``if "not found" in str(exc).lower()``, so the *prose* of a
message decided the public API's status code: rewording "Class not found" or
adding the words "not found" to any other message silently moved an endpoint
between 404 and 400, and no test could see it.

Every test here drives the mapping through an exception TYPE with a message
chosen to prove the message is irrelevant:

* the 404 type carries a message with NO "not found" in it — under the old
  substring dispatch it would have been a 400;
* the 400 types carry messages that DO contain "not found" — under the old
  substring dispatch they would have been 404s.

So these tests still pass when somebody rewords a message, and fail the moment
somebody remaps a type. ``test_every_checkin_error_type_is_mapped`` closes the
loop: a new ``CheckinError`` subclass that nobody assigned a status/code to
fails here rather than silently inheriting the base's fallback.

**The wire shape is also locked here.** Each rejection body carries a plain
STRING ``detail`` plus a SIBLING ``code`` — the stable discriminator clients
switch on. ``detail`` must never become an object: the CRM's
``_extractDetail`` reads ``data['detail']`` only when it is a String, so a
nested shape would degrade every real message to "Server error 400".

**And the delivery path is locked here too.** Every one of these bodies is
written by the single global handler in ``src/main.py``, which the routers
reach by RE-RAISING the typed error from an ``except CheckinError`` arm that
sits above their ``except Exception -> 500`` arm. If that re-raise were ever
replaced by something the generic arm could swallow, every parametrized test
below would flip to 500 — that is the proof the two arms cannot fight.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.checkin import checkin_exceptions
from src.checkin.checkin_exceptions import (
    CheckinClassDeletedError,
    CheckinClassFullError,
    CheckinClassInactiveError,
    CheckinClassNotFoundError,
    CheckinError,
    CheckinErrorCode,
    CheckinNotOpenYetError,
    CheckinOccurrenceCancelledError,
    CheckinOccurrenceNotFoundError,
)
from src.checkin.schema.checkin_schema import Attendee
from src.main import app

# Deliberately message-hostile fixtures: the 404 type's message avoids the
# words the old dispatch keyed on, and every 400 type's message contains them.
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such class at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"

# The whole public contract, in one table. Read it as: this type, that status,
# that stable code. Renaming a code is a BREAKING change for every client that
# switches on it (the CRM kiosk) — add a new one instead.
_TYPE_TO_CONTRACT: tuple[tuple[type[CheckinError], int, CheckinErrorCode], ...] = (
    (CheckinClassNotFoundError, 404, CheckinErrorCode.class_not_found),
    (CheckinClassDeletedError, 400, CheckinErrorCode.class_deleted),
    (CheckinClassInactiveError, 400, CheckinErrorCode.class_inactive),
    (
        CheckinOccurrenceNotFoundError,
        400,
        CheckinErrorCode.occurrence_not_found,
    ),
    (
        CheckinOccurrenceCancelledError,
        400,
        CheckinErrorCode.occurrence_cancelled,
    ),
    (CheckinNotOpenYetError, 400, CheckinErrorCode.checkin_not_open),
    (CheckinClassFullError, 400, CheckinErrorCode.class_full),
)

_TYPE_TO_STATUS: tuple[tuple[type[CheckinError], int], ...] = tuple(
    (exc_type, expected) for exc_type, expected, _ in _TYPE_TO_CONTRACT
)

_400_TYPES = tuple(t for t, s in _TYPE_TO_STATUS if s == 400)


def _message_for(status_code: int) -> str:
    """A message that would push the OPPOSITE way under substring dispatch."""
    return (
        _MSG_WITHOUT_THE_MAGIC_WORDS
        if status_code == 404
        else _MSG_WITH_THE_MAGIC_WORDS
    )


def _assert_error_body(body: dict, expected_code: CheckinErrorCode) -> None:
    """The wire shape: a plain-string ``detail`` + a sibling ``code``."""
    assert isinstance(body["detail"], str), body
    assert body["code"] == expected_code.value, body


def _a_real_validation_error() -> ValidationError:
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``.

    Used to prove a blanket ``except ValueError`` arm would misclassify an
    internal serialization failure as a 4xx.
    """
    try:
        Attendee.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("Attendee.model_validate({}) unexpectedly succeeded")


# ── the hierarchy itself ────────────────────────────────────────────────


def test_every_checkin_error_subclasses_value_error() -> None:
    """The base is a ``ValueError`` subclass on purpose: every pre-existing
    ``except ValueError`` (this router's own fallback, the member-portal
    sign-up handler, the batch's per-member isolation) keeps working
    unchanged, so the typed hierarchy is additive rather than a breaking
    sweep."""
    assert issubclass(CheckinError, ValueError)
    for exc_type, _ in _TYPE_TO_STATUS:
        assert issubclass(exc_type, CheckinError)
        assert issubclass(exc_type, ValueError)


def _concrete_error_types() -> set[type[CheckinError]]:
    """Every concrete ``CheckinError`` subclass defined in the module."""
    return {
        obj
        for obj in vars(checkin_exceptions).values()
        if isinstance(obj, type)
        and issubclass(obj, CheckinError)
        and obj is not CheckinError
    }


def test_every_checkin_error_type_is_mapped() -> None:
    """Every concrete ``CheckinError`` in the module carries an explicit
    status AND code in the table above. Adding a new one without deciding
    them fails HERE, instead of silently defaulting in production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _, _ in _TYPE_TO_CONTRACT
    }


def test_every_type_declares_its_own_status_and_code() -> None:
    """A new subclass must DECLARE both attributes, never inherit them.

    The base carries safe fallbacks so a not-yet-classified subclass can't
    500 a live request — this test is what makes forgetting them loud. It
    reads each class's OWN ``vars()``, so an inherited value fails.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"
        assert "code" in own, f"{exc_type.__name__} inherits code"
        assert own["code"] is not CheckinErrorCode.checkin_error, (
            f"{exc_type.__name__} reuses the base fallback code"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type itself is the single source of truth the global handler reads,
    so the class attributes and the table must agree exactly."""
    for exc_type, expected_status, expected_code in _TYPE_TO_CONTRACT:
        assert exc_type.status_code == expected_status, exc_type.__name__
        assert exc_type.code is expected_code, exc_type.__name__


def test_codes_are_unique() -> None:
    """Two types sharing a code would make the discriminator ambiguous."""
    codes = [code for _, _, code in _TYPE_TO_CONTRACT]
    assert len(set(codes)) == len(codes)


def test_pydantic_validation_error_is_a_value_error() -> None:
    """The hazard every blanket ``except ValueError`` arm carries.

    Documented here because it is the whole reason the roster read and the
    check-in removal no longer catch bare ``ValueError``: an internal
    serialization failure must be a logged 500, not a 4xx carrying a raw
    validation dump as ``detail``.
    """
    assert issubclass(ValidationError, ValueError)


# ── POST /api/v1/checkin ────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("exc_type", "expected", "expected_code"), _TYPE_TO_CONTRACT
)
def test_checkin_maps_error_type_to_status_and_code(
    client,
    auth_headers,
    fake_member_id,
    fake_gym_id,
    exc_type,
    expected,
    expected_code,
) -> None:
    """The single check-in maps the resolver's exception TYPE to its status
    AND its stable code — and the typed error reaches the global formatter
    rather than being swallowed by the handler's ``except Exception`` -> 500
    arm (a 500 here is exactly what that regression would look like)."""
    resolver = MagicMock()
    resolver.resolve = AsyncMock(side_effect=exc_type(_message_for(expected)))
    app.container.checkin_class_resolver.override(resolver)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_class_resolver.reset_override()

    assert resp.status_code == expected, resp.text
    # The detail is passed through verbatim — the refactor changes the
    # DISPATCH and ADDS a sibling code, never the detail's type or text.
    assert resp.json()["detail"] == _message_for(expected)
    _assert_error_body(resp.json(), expected_code)


def test_checkin_foreign_value_error_still_400(
    client, auth_headers, fake_member_id, fake_gym_id
) -> None:
    """A non-domain ``ValueError`` keeps the generic bad-input mapping (400),
    never a 500 — the reason the hierarchy subclasses ``ValueError``."""
    resolver = MagicMock()
    resolver.resolve = AsyncMock(side_effect=ValueError("something odd"))
    app.container.checkin_class_resolver.override(resolver)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_class_resolver.reset_override()

    assert resp.status_code == 400, resp.text
    # A foreign ValueError carries no code — clients fall back to detail.
    assert "code" not in resp.json()


def test_checkin_unexpected_exception_still_500(
    client, auth_headers, fake_member_id, fake_gym_id
) -> None:
    """The generic ``except Exception`` -> 500 fallback is untouched."""
    resolver = MagicMock()
    resolver.resolve = AsyncMock(side_effect=RuntimeError("db down"))
    app.container.checkin_class_resolver.override(resolver)
    try:
        resp = client.post(
            "/api/v1/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_class_resolver.reset_override()

    assert resp.status_code == 500, resp.text
    assert resp.json()["detail"] == "Failed to record check-in"


# ── POST /api/v1/checkin/batch ──────────────────────────────────────────


@pytest.mark.parametrize(
    ("exc_type", "expected", "expected_code"), _TYPE_TO_CONTRACT
)
def test_batch_checkin_maps_error_type_to_status_and_code(
    client, auth_headers, fake_gym_id, exc_type, expected, expected_code
) -> None:
    """The batch resolves the occurrence once, before any per-member work, so
    the same type -> (status, code) table decides the WHOLE request."""
    service = MagicMock()
    service.batch_checkin = AsyncMock(
        side_effect=exc_type(_message_for(expected))
    )
    app.container.batch_checkin_service.override(service)
    try:
        resp = client.post(
            "/api/v1/checkin/batch",
            json={
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "member_ids": [str(uuid4())],
            },
            headers=auth_headers,
        )
    finally:
        app.container.batch_checkin_service.reset_override()

    assert resp.status_code == expected, resp.text
    assert resp.json()["detail"] == _message_for(expected)
    _assert_error_body(resp.json(), expected_code)


# ── POST /api/v1/signup ─────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("exc_type", "expected", "expected_code"), _TYPE_TO_CONTRACT
)
def test_signup_maps_error_type_to_status_and_code(
    client, auth_headers, fake_gym_id, exc_type, expected, expected_code
) -> None:
    """Sign-up maps the same types the same way (it adds the cancelled-day and
    class-full ones the check-in path can't raise)."""
    service = MagicMock()
    service.create = AsyncMock(side_effect=exc_type(_message_for(expected)))
    app.container.signup_service.override(service)
    try:
        resp = client.post(
            "/api/v1/signup",
            json={
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

    assert resp.status_code == expected, resp.text
    assert resp.json()["detail"] == _message_for(expected)
    _assert_error_body(resp.json(), expected_code)


# ── DELETE /api/v1/checkin ──────────────────────────────────────────────


def _remove_checkin(client, auth_headers, gym_id: str):
    """DELETE /api/v1/checkin for a throwaway member/class."""
    return client.request(
        "DELETE",
        "/api/v1/checkin",
        params={
            "member_id": str(uuid4()),
            "gym_id": gym_id,
            "class_id": str(uuid4()),
            "occurrence_date": "2026-06-01",
            "occurrence_time": "17:00:00",
        },
        headers=auth_headers,
    )


def test_remove_checkin_maps_class_not_found_to_404(
    client, auth_headers, fake_gym_id
) -> None:
    """The remover only rejects on a missing class -> 404, by type."""
    remover = MagicMock()
    remover.remove = AsyncMock(
        side_effect=CheckinClassNotFoundError(_MSG_WITHOUT_THE_MAGIC_WORDS)
    )
    app.container.checkin_remover.override(remover)
    try:
        resp = _remove_checkin(client, auth_headers, fake_gym_id)
    finally:
        app.container.checkin_remover.reset_override()

    assert resp.status_code == 404, resp.text
    assert resp.json()["detail"] == _MSG_WITHOUT_THE_MAGIC_WORDS
    _assert_error_body(resp.json(), CheckinErrorCode.class_not_found)


def test_remove_checkin_validation_error_is_a_500_not_a_404(
    client, auth_headers, fake_gym_id
) -> None:
    """A pydantic ``ValidationError`` is an INTERNAL failure -> 500.

    This handler used to map ANY ``ValueError`` to 404, and ``ValidationError``
    subclasses ``ValueError`` — so a malformed ``CheckinRemoveResponse`` came
    back as a 404 whose ``detail`` was a raw validation dump. It is a logged
    500 now.
    """
    remover = MagicMock()
    remover.remove = AsyncMock(side_effect=_a_real_validation_error())
    app.container.checkin_remover.override(remover)
    try:
        resp = _remove_checkin(client, auth_headers, fake_gym_id)
    finally:
        app.container.checkin_remover.reset_override()

    assert resp.status_code == 500, resp.text
    assert resp.json()["detail"] == "Failed to remove check-in"


# ── GET /api/v1/checkin/attendees ───────────────────────────────────────


def test_attendees_validation_error_is_a_500_not_a_404(
    client, auth_headers, fake_gym_id
) -> None:
    """The roster read raises no domain error, so its old blanket
    ``except ValueError -> 404`` could only ever fire on an internal failure —
    returning a 404 whose ``detail`` was a raw pydantic dump. Now a 500."""
    service = MagicMock()
    service.list_attendees = AsyncMock(side_effect=_a_real_validation_error())
    app.container.checkin_attendees_service.override(service)
    try:
        resp = client.get(
            "/api/v1/checkin/attendees",
            params={
                "gym_id": fake_gym_id,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_attendees_service.reset_override()

    assert resp.status_code == 500, resp.text
    assert resp.json()["detail"] == "Failed to list attendees"


# ── the anti-regression pair, stated explicitly ─────────────────────────


def test_prose_no_longer_decides_the_status(
    client, auth_headers, fake_member_id, fake_gym_id
) -> None:
    """Both directions of the old bug, in one place.

    A 404 type whose message lacks "not found" must still 404, and a 400 type
    whose message CONTAINS "not found" must still 400. Under the substring
    dispatch this test failed twice over — which is exactly why the live kiosk
    saw an opaque 400 for "Class is not active".
    """
    def _post(exc: CheckinError) -> int:
        resolver = MagicMock()
        resolver.resolve = AsyncMock(side_effect=exc)
        app.container.checkin_class_resolver.override(resolver)
        try:
            return client.post(
                "/api/v1/checkin",
                json={
                    "member_id": fake_member_id,
                    "gym_id": fake_gym_id,
                    "class_id": str(uuid4()),
                    "occurrence_date": "2026-06-01",
                    "occurrence_time": "17:00:00",
                },
                headers=auth_headers,
            ).status_code
        finally:
            app.container.checkin_class_resolver.reset_override()

    assert _post(CheckinClassNotFoundError("gone, vanished, absent")) == 404
    for exc_type in _400_TYPES:
        assert _post(exc_type("Class not found — but still a 400")) == 400
