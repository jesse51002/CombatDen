"""The waivers domain's exception TYPE -> HTTP status contract.

The TYPE decides the status, never the message text. Every test drives the
mapping through a type whose message points the OPPOSITE way — the 404 types'
lacks "not found", the 400 types' contains it, the 409 type's contains neither
"reload" nor "not found" — so rewording a message passes and remapping a type
fails. Don't "fix" those fixtures to read naturally. The 409 is the sharpest
case: nothing about the word "reload" says "conflict", so a copy edit that
demoted a version-lock conflict to a 400 would invite a client to re-submit the
same stale version forever.

**The wire shape is a plain-string ``detail`` and nothing else, by decision.**
A sibling ``code`` is opt-in per domain and earns its keep only where a client
branches on a specific rejection (``checkin``); the CRM's sign surfaces branch
on 409-vs-404-vs-400 and render ``detail`` as prose. A code declared here could
not even reach the wire without the global formatter in ``src/main.py``.

**The blanket-``except ValueError`` trap is locked too.** ``ValidationError``
subclasses ``ValueError``, so a blanket arm on a handler whose service raises no
bad-input ``ValueError`` can only ever fire on our own bug. ``PUT /waivers/``
KEEPS its generic arm — ``validate_mutable_columns`` really does raise one.
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

# Message-hostile on purpose: the 404 message avoids "not found", the 400 one
# contains it, and the 409 one carries neither it nor "reload".
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such document at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"
_MSG_WITHOUT_RELOAD = "the text moved on while you were reading it"

# The public contract, in one table. No ``code`` column — see the docstring.
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
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``, so a
    blanket ``except ValueError`` arm misclassifies an internal failure as 4xx."""
    try:
        WaiverResponse.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("empty WaiverResponse unexpectedly valid")


# ── the endpoints whose status is decided by the exception type ─────────
#
# Each entry: (label, the WaiversService method the handler awaits, a callable
# issuing the request).


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

    Waivers is an INPUT-VALIDATION domain, not a money one: an unmapped
    rejection must land as a 400, not a 500. It also keeps the hierarchy
    additive for the existing ``except ValueError`` arms (this router's, and
    the members router's linked-account ones).
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
    """Adding a subclass without deciding its status fails HERE, rather than
    silently defaulting in production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _ in _TYPE_TO_STATUS
    }


def test_every_type_declares_its_own_status_code() -> None:
    """A subclass must DECLARE ``status_code``, never inherit it.

    The base's 400 fallback keeps an unclassified subclass from 500-ing a live
    request; this reads each class's OWN ``vars()`` so forgetting is loud.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"


def test_no_type_declares_a_machine_readable_code() -> None:
    """``waivers`` deliberately has no ``code`` machinery.

    A code cannot reach the wire without the global formatter in
    ``src/main.py``, and no client branches on one — so declaring values would
    test-lock invisible strings into the public contract. If a code is ever
    needed, the enum and the formatter land in the SAME change as this test.
    """
    assert not hasattr(waivers_exceptions, "WaiversErrorCode")
    for exc_type in _concrete_error_types() | {WaiversError}:
        assert not hasattr(exc_type, "code"), (
            f"{exc_type.__name__} declares a `code` that cannot reach the "
            "wire — register the global handler in src/main.py in the same "
            "change, or drop it"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type is what the routers read, so the class attributes and the table
    must agree exactly."""
    for exc_type, expected_status in _TYPE_TO_STATUS:
        assert exc_type.status_code == expected_status, exc_type.__name__


def test_pydantic_validation_error_is_a_value_error() -> None:
    """The hazard every blanket ``except ValueError`` arm carries — and the
    reason the typed-only handlers catch no bare ``ValueError``: an internal
    serialization failure must be a logged 500, not a 4xx claiming the waiver
    is missing.
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
    """Every handler maps the service's exception TYPE to its status.

    Parametrized over the WHOLE table on every endpoint, not just the types a
    handler can raise today: the status must come off the type regardless of
    which route the raise travels through. Without that symmetry one raise
    (``get_payer_auth_waiver_for_member``) answers 404 on the read route and
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
    # ``detail`` is passed through verbatim; only the dispatch is by type.
    assert resp.json()["detail"] == _message_for(expected), label
    assert isinstance(resp.json()["detail"], str), label


def test_the_wire_shape_is_status_plus_detail_only(
    client, auth_headers, fake_gym_id
) -> None:
    """The whole wire shape: a status and a plain-string ``detail``.

    An EQUALITY on the body, not a subset, so nothing can quietly grow a second
    key. If a sibling ``code`` is ever added, THIS test changes in the same
    commit as the enum and the global formatter.
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


# ── the 409, independent of the word "reload" ──────────────────────────


def test_stale_version_is_a_409_without_the_word_reload(
    client, auth_headers, fake_gym_id
) -> None:
    """The version-lock conflict is a 409 because of its TYPE.

    Stated on its own because it is the sharpest edge: this message contains
    neither "reload" nor "not found", and a 400 here would tell the client its
    request was malformed when the document had simply moved. Only the 409
    makes "fetch the new version and sign that" the obvious next step.
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
    """Every direction, in one place: a 404 type whose message lacks "not
    found" still 404s; a 400 type whose message CONTAINS it still 400s; and the
    409 type stays a 409 even when its message says "not found" — the third
    wrong answer prose dispatch produces.
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


# ── the blanket-except-ValueError trap, both directions ─────────────────


def test_update_waiver_immutable_column_value_error_is_still_400(
    client, auth_headers, fake_gym_id
) -> None:
    """``PUT /waivers/`` KEEPS its generic bad-input arm.

    Its service really does raise a plain ``ValueError`` — the shared
    ``validate_mutable_columns`` guard rejects an immutable column that way on
    a rename, and that is a caller error (400), not an internal failure.
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

    These services raise only typed ``WaiversError``s, so a blanket
    ``except ValueError`` arm could ONLY fire on our own bug. ``GET
    /waivers/{id}`` bites hardest: a 404 there reports a waiver staff can see
    in the list as missing, whenever its stored row stops fitting the schema.
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
