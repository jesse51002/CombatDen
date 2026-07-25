"""The check-in domain's exception TYPE -> (HTTP status, ``code``) contract.

The TYPE decides the status, never the message text. Every test drives the
mapping through a type whose message points the OPPOSITE way (the 404 type's
lacks "not found"; the 400 types' contain it), so rewording a message passes
and remapping a type fails — don't "fix" those fixtures to read naturally.

Two more things are locked here. **The wire shape**: a plain-STRING ``detail``
plus a sibling ``code``, the stable discriminator clients switch on. An object
``detail`` would degrade every message to "Server error 400" in the CRM, whose
``_extractDetail`` reads it only when it is a String. **The delivery path**:
these bodies come from the one global handler in ``src/main.py``, reached
because each router re-raises the typed error above its
``except Exception -> 500`` arm — break that and every test below flips to 500.
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

# Message-hostile on purpose: the 404 message avoids "not found", the 400 one
# contains it.
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such class at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"

# The public contract, in one table. Renaming a code BREAKS every client that
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
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``, so a
    blanket ``except ValueError`` arm misclassifies an internal failure as 4xx."""
    try:
        Attendee.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("Attendee.model_validate({}) unexpectedly succeeded")


# ── the hierarchy itself ────────────────────────────────────────────────


def test_every_checkin_error_subclasses_value_error() -> None:
    """The base is a ``ValueError`` subclass on purpose: every existing
    ``except ValueError`` arm (this router's fallback, the member-portal
    sign-up handler, the batch's per-member isolation) keeps working, so the
    typed hierarchy is additive rather than a breaking sweep."""
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
    """Adding a subclass without deciding its status + code fails HERE, rather
    than silently defaulting in production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _, _ in _TYPE_TO_CONTRACT
    }


def test_every_type_declares_its_own_status_and_code() -> None:
    """A subclass must DECLARE both attributes, never inherit them.

    The base's fallbacks keep an unclassified subclass from 500-ing a live
    request; this reads each class's OWN ``vars()`` so forgetting is loud.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"
        assert "code" in own, f"{exc_type.__name__} inherits code"
        assert own["code"] is not CheckinErrorCode.checkin_error, (
            f"{exc_type.__name__} reuses the base fallback code"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type is what the global handler reads, so the class attributes and
    the table must agree exactly."""
    for exc_type, expected_status, expected_code in _TYPE_TO_CONTRACT:
        assert exc_type.status_code == expected_status, exc_type.__name__
        assert exc_type.code is expected_code, exc_type.__name__


def test_codes_are_unique() -> None:
    """Two types sharing a code would make the discriminator ambiguous."""
    codes = [code for _, _, code in _TYPE_TO_CONTRACT]
    assert len(set(codes)) == len(codes)


def test_pydantic_validation_error_is_a_value_error() -> None:
    """The hazard every blanket ``except ValueError`` arm carries — and the
    reason the roster read and the check-in removal catch only typed errors:
    an internal serialization failure must be a logged 500, not a 4xx carrying
    a raw validation dump as ``detail``."""
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
    """Type -> status + code on the single check-in. A 500 here means the
    handler's ``except Exception`` arm swallowed the typed error."""
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
    # ``detail`` is passed through verbatim; only the dispatch is by type.
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
    """A non-``ValueError`` still lands on the generic 500 fallback."""
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
    """Sign-up maps the same types the same way (plus the cancelled-day and
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

    The remover raises only ``CheckinClassNotFoundError``, so a blanket
    ``except ValueError`` arm here could only ever fire on our own bug — and
    would answer 404 with a raw validation dump as ``detail``.
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
    """The roster read raises no domain error, so a blanket
    ``except ValueError -> 404`` could only ever fire on an internal failure.
    It stays a logged 500."""
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


# ── prose must never decide the status ─────────────────────────────────


def test_prose_no_longer_decides_the_status(
    client, auth_headers, fake_member_id, fake_gym_id
) -> None:
    """Both directions in one place: a 404 type whose message lacks "not found"
    still 404s, and a 400 type whose message CONTAINS it still 400s. Status by
    prose is what showed the live kiosk an opaque 400 for "Class is not active".
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
