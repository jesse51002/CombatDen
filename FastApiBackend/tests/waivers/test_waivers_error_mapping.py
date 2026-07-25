"""The waivers domain's exception TYPE -> HTTP status contract.

This is the regression the routers could not previously catch. Every waiver
handler picked its status by grepping the message — ``if "not found" in
str(exc).lower()`` for the 404 and, on the two signing paths, ``if "reload" in
str(exc).lower()`` for the 409 — so the *prose* of a message was part of the
public API.

The ``"reload"`` coupling was the worse of the two, because nothing about that
word says "conflict". Rewording ``"Waiver was updated since it was displayed —
reload and sign the current version"`` to drop it — a pure copy edit, and a
plausible one — silently demoted the version-lock conflict from a 409 to a
400, which is the difference between "reload, the text changed" and "your
request was malformed". A client told the latter can reasonably retry the same
stale version forever.

Every test here drives the mapping through an exception TYPE with a message
chosen to prove the message is irrelevant:

* the 404 types carry a message with NO "not found" in it — under the old
  substring dispatch they would have been 400s;
* the 400 types carry a message that DOES contain "not found" — under the old
  dispatch each would have been a 404;
* the 409 type carries a message with NEITHER "reload" NOR "not found" — under
  the old dispatch it would have been a 400.

So these tests still pass when somebody rewords a message, and fail the moment
somebody remaps a type. ``test_every_waivers_error_type_is_mapped`` closes the
loop: a new ``WaiversError`` subclass that nobody assigned a status to fails
here rather than silently inheriting the base's fallback.

**The wire shape is a plain-string ``detail`` and nothing else, by decision** —
the same call as ``members``. A sibling machine-readable ``code`` is opt-in per
domain and earns its keep only where a client branches on a specific rejection
(``checkin``, whose kiosk picks its blocked-screen copy from it). The CRM's sign
surfaces branch on 409-vs-404-vs-400 and render ``detail`` as prose, so a code
here would be declared, test-locked and invisible — it cannot even reach the
wire without the one global ``app.add_exception_handler`` formatter in
``src/main.py``.

**The blanket-``except ValueError`` traps are locked here too.** pydantic's
``ValidationError`` subclasses ``ValueError``, so a blanket arm on a handler
whose service raises no bad-input ``ValueError`` can only ever fire on an
internal failure. ``GET /waivers/{id}`` mapped ANY ``ValueError`` to 404, so a
waiver whose stored body no longer fit ``WaiverResponse`` reported itself as
missing. ``PUT /waivers/`` KEEPS a generic arm, because the shared
``validate_mutable_columns`` guard really does raise a plain ``ValueError`` for
an immutable column on a rename.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.waivers import waivers_exceptions
from src.waivers.schema.waivers_schema import WaiverResponse
from src.waivers.waivers_exceptions import (
    WaiverNoCurrentVersionError,
    WaiverNotFoundError,
    WaiverPayerAuthMissingError,
    WaiverPayerAuthNotArchivableError,
    WaiversError,
    WaiverSignerNotInGymError,
    WaiverVersionNotFoundError,
    WaiverVersionStaleError,
)

# Deliberately message-hostile fixtures. The 404 message avoids the words the
# old dispatch keyed on; the 400 message contains them; the 409 message
# contains NEITHER "reload" nor "not found", so under the old dispatch it fell
# all the way through to the bad-request arm.
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such document at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"
_MSG_WITHOUT_RELOAD = "the text moved on while you were reading it"

# The whole public contract, in one table: this type, that status. There is no
# machine-readable ``code`` column — see the module docstring.
_TYPE_TO_STATUS: tuple[tuple[type[WaiversError], int], ...] = (
    (WaiverNotFoundError, 404),
    (WaiverVersionNotFoundError, 404),
    (WaiverSignerNotInGymError, 404),
    (WaiverPayerAuthMissingError, 404),
    (WaiverNoCurrentVersionError, 400),
    (WaiverPayerAuthNotArchivableError, 400),
    (WaiverVersionStaleError, 409),
)

_400_TYPES = tuple(t for t, s in _TYPE_TO_STATUS if s == 400)
_404_TYPES = tuple(t for t, s in _TYPE_TO_STATUS if s == 404)


def _message_for(status_code: int) -> str:
    """A message that would push the OPPOSITE way under substring dispatch."""
    if status_code == 400:
        return _MSG_WITH_THE_MAGIC_WORDS
    if status_code == 409:
        return _MSG_WITHOUT_RELOAD
    return _MSG_WITHOUT_THE_MAGIC_WORDS


def _a_real_validation_error() -> ValidationError:
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``.

    Used to prove a blanket ``except ValueError`` arm would misclassify an
    internal serialization failure as a 4xx.
    """
    try:
        WaiverResponse.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("empty WaiverResponse unexpectedly valid")


# ── the endpoints whose status is decided by the exception type ─────────
#
# Each entry: (label, the WaiversService method the handler awaits, a callable
# issuing the request). Every one of these used to pick its status by matching
# words in the message.


def _post_waiver(client, headers, waiver_id, gym_id):
    return client.post(
        "/api/v1/waivers/",
        json={"gym_id": gym_id, "name": "Liability", "body": "# body"},
        headers=headers,
    )


def _put_waiver(client, headers, waiver_id, gym_id):
    return client.put(
        "/api/v1/waivers/",
        json={
            "waiver_id": waiver_id,
            "gym_id": gym_id,
            "data": {"name": "Renamed"},
        },
        headers=headers,
    )


def _delete_waiver(client, headers, waiver_id, gym_id):
    return client.delete(
        f"/api/v1/waivers/?waiver_id={waiver_id}&gym_id={gym_id}",
        headers=headers,
    )


def _get_waiver(client, headers, waiver_id, gym_id):
    return client.get(
        f"/api/v1/waivers/{waiver_id}?gym_id={gym_id}",
        headers=headers,
    )


def _sign_waiver(client, headers, waiver_id, gym_id):
    return client.post(
        f"/api/v1/waivers/{waiver_id}/signatures",
        json={
            "gym_id": gym_id,
            "member_id": str(uuid4()),
            "waiver_version_id": str(uuid4()),
            "signer_name": "Jane Doe",
            "consent_acknowledged": True,
        },
        headers=headers,
    )


_ENDPOINTS = (
    ("POST /waivers/", "create_waiver", _post_waiver),
    ("PUT /waivers/", "update_waiver", _put_waiver),
    ("DELETE /waivers/", "delete_waiver", _delete_waiver),
    ("GET /waivers/{id}", "get_waiver", _get_waiver),
    ("POST /waivers/{id}/signatures", "sign_waiver", _sign_waiver),
)


def _call_with_service_error(
    client, headers, waiver_id, gym_id, method_name, call, exc
):
    """Issue ``call`` with the waivers service raising ``exc``."""
    waivers = MagicMock()
    setattr(waivers, method_name, AsyncMock(side_effect=exc))
    container = client.app.container
    container.waivers_service.override(waivers)
    try:
        return call(client, headers, waiver_id, gym_id)
    finally:
        container.waivers_service.reset_override()


# ── the hierarchy itself ────────────────────────────────────────────────


def test_every_waivers_error_subclasses_value_error() -> None:
    """The base is a ``ValueError`` subclass on purpose.

    Waivers is an INPUT-VALIDATION domain, not a money / external-system one:
    an unmapped waiver rejection must land as a 400 bad-request, not a 500. It
    also keeps the hierarchy additive — every pre-existing
    ``except ValueError`` arm (this router's own, and the members router's
    linked-account arms) behaves exactly as it did before.
    """
    assert issubclass(WaiversError, ValueError)
    for exc_type, _ in _TYPE_TO_STATUS:
        assert issubclass(exc_type, WaiversError)
        assert issubclass(exc_type, ValueError)


def _concrete_error_types() -> set[type[WaiversError]]:
    """Every concrete ``WaiversError`` subclass defined in the module."""
    return {
        obj
        for obj in vars(waivers_exceptions).values()
        if isinstance(obj, type)
        and issubclass(obj, WaiversError)
        and obj is not WaiversError
    }


def test_every_waivers_error_type_is_mapped() -> None:
    """Every concrete ``WaiversError`` in the module carries an explicit
    status in the table above. Adding a new one without deciding it fails
    HERE, instead of silently defaulting in production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _ in _TYPE_TO_STATUS
    }


def test_every_type_declares_its_own_status_code() -> None:
    """A new subclass must DECLARE ``status_code``, never inherit it.

    The base carries a safe 400 fallback so a not-yet-classified subclass
    can't 500 a live request — this test is what makes forgetting it loud. It
    reads each class's OWN ``vars()``, so an inherited value fails.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"


def test_no_type_declares_a_machine_readable_code() -> None:
    """``waivers`` deliberately has no ``code`` machinery.

    Same call as ``members``: a code cannot reach the wire without the global
    formatter in ``src/main.py``, and no client branches on one, so declaring
    values would test-lock strings into the public contract while staying
    invisible. If a code is ever needed, the enum and the formatter land in
    the same change — and this test is where that decision surfaces.
    """
    assert not hasattr(waivers_exceptions, "WaiversErrorCode")
    for exc_type in _concrete_error_types() | {WaiversError}:
        assert not hasattr(exc_type, "code"), (
            f"{exc_type.__name__} declares a `code` that cannot reach the "
            "wire — register the global handler in src/main.py in the same "
            "change, or drop it"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type itself is the single source of truth the routers read, so the
    class attributes and the table must agree exactly."""
    for exc_type, expected_status in _TYPE_TO_STATUS:
        assert exc_type.status_code == expected_status, exc_type.__name__


def test_pydantic_validation_error_is_a_value_error() -> None:
    """The hazard every blanket ``except ValueError`` arm carries.

    Documented here because it is the whole reason the typed-only handlers no
    longer catch bare ``ValueError``: an internal serialization failure must
    be a logged 500, not a 4xx claiming the waiver is missing.
    """
    assert issubclass(ValidationError, ValueError)


# ── the type -> status mapping, per endpoint ────────────────────────────


@pytest.mark.parametrize(("label", "method_name", "call"), _ENDPOINTS)
@pytest.mark.parametrize(("exc_type", "expected"), _TYPE_TO_STATUS)
def test_endpoint_maps_error_type_to_status(
    client,
    auth_headers,
    fake_gym_id,
    label,
    method_name,
    call,
    exc_type,
    expected,
) -> None:
    """Every converted handler maps the service's exception TYPE to its
    status — with a message that would have pushed the OPPOSITE way under the
    old substring dispatch.

    Parametrized over the WHOLE table on every endpoint, not just the types a
    given handler can raise today: the status must come off the type
    regardless of which route the raise travels through. That symmetry is the
    property that broke before — one raise
    (``get_payer_auth_waiver_for_member``) answered 404 on the read route and
    400 on the link route.
    """
    waiver_id = str(uuid4())
    resp = _call_with_service_error(
        client,
        auth_headers,
        waiver_id,
        str(fake_gym_id),
        method_name,
        call,
        exc_type(_message_for(expected)),
    )

    assert resp.status_code == expected, f"{label}: {resp.text}"
    # The detail is passed through verbatim — the refactor changes the
    # DISPATCH, never the detail's type or text.
    assert resp.json()["detail"] == _message_for(expected), label
    assert isinstance(resp.json()["detail"], str), label


def test_the_wire_shape_is_status_plus_detail_only(
    client, auth_headers, fake_gym_id
) -> None:
    """The whole wire shape: a status and a plain-string ``detail``.

    Asserted as an EQUALITY on the body, not a subset, so nothing can quietly
    grow a second key. See the module docstring for why there is no sibling
    ``code``; if one is ever added, THIS is the test that has to change, in
    the same commit as the enum and the global formatter.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        str(uuid4()),
        str(fake_gym_id),
        "get_waiver",
        _get_waiver,
        WaiverNotFoundError(_MSG_WITHOUT_THE_MAGIC_WORDS),
    )

    assert resp.status_code == 404, resp.text
    assert resp.json() == {"detail": _MSG_WITHOUT_THE_MAGIC_WORDS}


# ── the 409 that used to hang off the word "reload" ─────────────────────


def test_stale_version_is_a_409_without_the_word_reload(
    client, auth_headers, fake_gym_id
) -> None:
    """The version-lock conflict is a 409 because of its TYPE.

    Stated on its own because it is the sharpest edge this change removes: the
    message here contains neither "reload" nor "not found", so under the old
    dispatch it fell through to 400 — telling the client its request was
    malformed when in fact the document had moved. 409 is what makes "fetch
    the new version and sign that" the obvious next step.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        str(uuid4()),
        str(fake_gym_id),
        "sign_waiver",
        _sign_waiver,
        WaiverVersionStaleError(_MSG_WITHOUT_RELOAD),
    )

    assert resp.status_code == 409, resp.text
    assert "reload" not in resp.json()["detail"].lower()


def test_prose_no_longer_decides_the_status(
    client, auth_headers, fake_gym_id
) -> None:
    """Every direction of the old bug, in one place.

    A 404 type whose message lacks "not found" must still 404; a 400 type
    whose message CONTAINS "not found" must still 400; the 409 type must stay
    a 409 even when its message contains "not found" (which the old dispatch
    checked SECOND, after "reload" — so dropping "reload" from a message that
    happened to say "not found" produced a 404, a third wrong answer).
    """

    def _status(exc: WaiversError) -> int:
        return _call_with_service_error(
            client,
            auth_headers,
            str(uuid4()),
            str(fake_gym_id),
            "sign_waiver",
            _sign_waiver,
            exc,
        ).status_code

    for exc_type in _404_TYPES:
        assert _status(exc_type("Unknown document 123")) == 404, exc_type
    for exc_type in _400_TYPES:
        assert _status(exc_type("Waiver not found — but still a 400")) == 400
    assert _status(WaiverVersionStaleError("waiver not found? no: stale")) == 409


# ── the blanket-except-ValueError traps, both directions ────────────────


def test_update_waiver_immutable_column_value_error_is_still_400(
    client, auth_headers, fake_gym_id
) -> None:
    """``PUT /waivers/`` KEEPS its generic bad-input arm.

    Its service really does raise a plain ``ValueError``: the shared,
    domain-agnostic ``validate_mutable_columns`` guard rejects an immutable
    column that way on a rename, and that is a caller error (400), not an
    internal failure. Note the message contains "not found" and it is still a
    400 — the prose no longer decides anything.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        str(uuid4()),
        str(fake_gym_id),
        "update_waiver",
        _put_waiver,
        ValueError("Cannot update immutable columns: waiver_type (not found)"),
    )

    assert resp.status_code == 400, resp.text
    assert "immutable columns" in resp.json()["detail"]


@pytest.mark.parametrize(
    ("label", "method_name", "call"),
    [e for e in _ENDPOINTS if e[1] != "update_waiver"],
)
def test_typed_only_handler_turns_a_validation_error_into_a_500(
    client, auth_headers, fake_gym_id, label, method_name, call
) -> None:
    """A pydantic ``ValidationError`` is an INTERNAL failure -> 500.

    These handlers' services raise only typed ``WaiversError``s, so a blanket
    ``except ValueError`` arm could ONLY ever fire on an internal failure —
    and ``ValidationError`` subclasses ``ValueError``. ``GET /waivers/{id}``
    is the one that bit hardest: it mapped any ``ValueError`` to 404, so a
    waiver whose stored row no longer fits ``WaiverResponse`` reported itself
    as MISSING, and staff were told a document they can see in the list does
    not exist.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        str(uuid4()),
        str(fake_gym_id),
        method_name,
        call,
        _a_real_validation_error(),
    )

    assert resp.status_code == 500, f"{label}: {resp.text}"
    assert isinstance(resp.json()["detail"], str), label
    assert "not found" not in resp.json()["detail"].lower(), label
