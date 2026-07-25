"""The members domain's exception TYPE -> HTTP status contract.

Status must come off the exception's type, never from matching words in its
message — under prose dispatch a pure copy edit moves a status code and no test
notices. So every message here is chosen to push the OPPOSITE way: the 404
type's message omits "not found", every 400 type's contains it. These tests
survive a reworded message and fail the moment a type is remapped.

``members`` declares no machine-readable ``code``: a sibling ``code`` is opt-in
per domain and earns its keep only where a client branches on a rejection
(``checkin``). Nothing does here, and a code cannot reach the wire without the
global formatter in ``src/main.py`` — so one would be test-locked and invisible.
The wire-shape test pins that; if a code is ever needed, it fails alongside the
enum and formatter landing together.

The blanket-``except ValueError`` traps are locked too, both directions.
pydantic's ``ValidationError`` IS a ``ValueError``, so a blanket arm on a
handler whose service raises no bad-input ``ValueError`` can only fire on an
internal failure — a broken response model answered as a 4xx carrying a raw
validation dump instead of a logged 500. ``PUT /members/{id}`` keeps its arm
(``validate_mutable_columns`` really does raise a plain ``ValueError``); the
rest do not. The two member-DETAIL reads, the largest response model in the CRM,
are the worst case and get their own section at the bottom.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import ValidationError

from src.members import members_exceptions
from src.members.members_exceptions import (
    MemberGymStripeAccountMissingError,
    MemberNotFoundError,
    MemberNoUpdateFieldsError,
    MembersError,
    MemberStripeCustomerMissingError,
)
from src.members.schema.members_billing_schema import (
    MembersBillingProfileResponse,
)

# Deliberately message-hostile fixtures: the 404 type's message avoids the
# words the old dispatch keyed on, and every 400 type's message contains them.
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such member at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"

# The whole public contract, in one table: this type, that status. No
# machine-readable ``code`` column, deliberately (see the module docstring).
_TYPE_TO_STATUS: tuple[tuple[type[MembersError], int], ...] = (
    (MemberNotFoundError, 404),
    (MemberGymStripeAccountMissingError, 400),
    (MemberStripeCustomerMissingError, 400),
    (MemberNoUpdateFieldsError, 400),
)

_400_TYPES = tuple(t for t, s in _TYPE_TO_STATUS if s == 400)


def _message_for(status_code: int) -> str:
    """A message that would push the OPPOSITE way under substring dispatch."""
    return (
        _MSG_WITHOUT_THE_MAGIC_WORDS
        if status_code == 404
        else _MSG_WITH_THE_MAGIC_WORDS
    )


def _a_real_validation_error() -> ValidationError:
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``, so a
    blanket arm would misclassify an internal failure as a 4xx."""
    try:
        MembersBillingProfileResponse.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("empty MembersBillingProfileResponse unexpectedly valid")


# ── the endpoints whose status is decided by the exception type ─────────
#
# Each entry: (label, the management-service method the handler awaits, a
# callable issuing the request).


def _put_member(client, headers, member_id):
    return client.put(
        f"/api/v1/members/{member_id}",
        json={"data": {"first_name": "Ada"}},
        headers=headers,
    )


def _put_card(client, headers, member_id):
    return client.put(
        f"/api/v1/members/{member_id}/card",
        json={"payment_method_id": "pm_card_visa"},
        headers=headers,
    )


def _delete_payment(client, headers, member_id):
    return client.delete(
        f"/api/v1/members/{member_id}/payment",
        headers=headers,
    )


def _get_payment_method_status(client, headers, member_id):
    return client.get(
        f"/api/v1/members/{member_id}/payment-method-status",
        headers=headers,
    )


def _get_invoices(client, headers, member_id):
    return client.get(
        f"/api/v1/members/{member_id}/invoices",
        headers=headers,
    )


def _get_upcoming_invoice(client, headers, member_id):
    return client.get(
        f"/api/v1/members/{member_id}/upcoming-invoice",
        headers=headers,
    )


_ENDPOINTS = (
    ("PUT /members/{id}", "update_member", _put_member),
    ("PUT /members/{id}/card", "update_card", _put_card),
    ("DELETE /members/{id}/payment", "unlink_payment", _delete_payment),
    (
        "GET /members/{id}/payment-method-status",
        "has_payment_method",
        _get_payment_method_status,
    ),
    ("GET /members/{id}/invoices", "list_invoices", _get_invoices),
    (
        "GET /members/{id}/upcoming-invoice",
        "get_upcoming_invoice",
        _get_upcoming_invoice,
    ),
)


def _call_with_service_error(client, headers, member_id, method_name, call, exc):
    """Issue ``call`` with the management service raising ``exc``."""
    mgmt = MagicMock()
    setattr(mgmt, method_name, AsyncMock(side_effect=exc))
    container = client.app.container
    container.members_management_service.override(mgmt)
    try:
        return call(client, headers, member_id)
    finally:
        container.members_management_service.reset_override()


# ── the hierarchy itself ────────────────────────────────────────────────


def test_every_members_error_subclasses_value_error() -> None:
    """The base subclasses ``ValueError`` on purpose: every ``except
    ValueError`` arm elsewhere keeps working, so the typed hierarchy is
    additive rather than a breaking sweep."""
    assert issubclass(MembersError, ValueError)
    for exc_type, _ in _TYPE_TO_STATUS:
        assert issubclass(exc_type, MembersError)
        assert issubclass(exc_type, ValueError)


def _concrete_error_types() -> set[type[MembersError]]:
    """Every concrete ``MembersError`` subclass defined in the module."""
    return {
        obj
        for obj in vars(members_exceptions).values()
        if isinstance(obj, type)
        and issubclass(obj, MembersError)
        and obj is not MembersError
    }


def test_every_members_error_type_is_mapped() -> None:
    """Every concrete ``MembersError`` carries an explicit status in the table
    above — a new one nobody classified fails HERE, not silently in
    production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _ in _TYPE_TO_STATUS
    }


def test_every_type_declares_its_own_status_code() -> None:
    """A new subclass must DECLARE ``status_code``, never inherit it.

    The base's fallback keeps an unclassified subclass from 500-ing a live
    request; reading each class's OWN ``vars()`` is what makes forgetting loud.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"


def test_no_type_declares_a_machine_readable_code() -> None:
    """``members`` deliberately has no ``code`` machinery.

    A code cannot reach the wire without the global formatter in
    ``src/main.py``, so declaring one here would test-lock four strings into the
    public contract while staying invisible to every caller. This asserts
    against that half-wired state: enum and formatter land together or neither.
    """
    assert not hasattr(members_exceptions, "MembersErrorCode")
    for exc_type in _concrete_error_types() | {MembersError}:
        assert not hasattr(exc_type, "code"), (
            f"{exc_type.__name__} declares a `code` that cannot reach the "
            "wire — register the global handler in src/main.py in the same "
            "change, or drop it"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type is what the routers read, so its attributes and the table above
    must agree exactly."""
    for exc_type, expected_status in _TYPE_TO_STATUS:
        assert exc_type.status_code == expected_status, exc_type.__name__


def test_pydantic_validation_error_is_a_value_error() -> None:
    """The hazard every blanket ``except ValueError`` arm carries, and the whole
    reason the typed-only handlers catch no bare ``ValueError``: an internal
    serialization failure must be a logged 500, not a 4xx carrying a raw
    validation dump as ``detail``."""
    assert issubclass(ValidationError, ValueError)


# ── the type -> status mapping, per endpoint ────────────────────────────


@pytest.mark.parametrize(("label", "method_name", "call"), _ENDPOINTS)
@pytest.mark.parametrize(("exc_type", "expected"), _TYPE_TO_STATUS)
def test_endpoint_maps_error_type_to_status(
    client,
    auth_headers,
    fake_member_id,
    label,
    method_name,
    call,
    exc_type,
    expected,
) -> None:
    """Every handler maps the service's exception TYPE to its status — with a
    message that would push the OPPOSITE way under substring dispatch."""
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        method_name,
        call,
        exc_type(_message_for(expected)),
    )

    assert resp.status_code == expected, f"{label}: {resp.text}"
    # The detail passes through verbatim: the type decides the DISPATCH, never
    # the detail's type or text.
    assert resp.json()["detail"] == _message_for(expected), label
    assert isinstance(resp.json()["detail"], str), label


def test_the_wire_shape_is_status_plus_detail_only(
    client, auth_headers, fake_member_id
) -> None:
    """The whole wire shape: a status and a plain-string ``detail``.

    An EQUALITY on the body, not a subset, so nothing can quietly grow a second
    key. If a client ever does need a ``code``, THIS test changes in the same
    commit as the enum and the global formatter — its failing is the signal the
    wire shape moved.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        "has_payment_method",
        _get_payment_method_status,
        MemberNotFoundError(_MSG_WITHOUT_THE_MAGIC_WORDS),
    )

    assert resp.status_code == 404, resp.text
    assert resp.json() == {"detail": _MSG_WITHOUT_THE_MAGIC_WORDS}


# ── the blanket-except-ValueError traps, both directions ────────────────


def test_update_member_immutable_column_value_error_is_still_400(
    client, auth_headers, fake_member_id
) -> None:
    """``PUT /members/{id}`` KEEPS its generic bad-input arm.

    The shared ``validate_mutable_columns`` guard really does reject an
    immutable column with a plain ``ValueError``, and that is a caller error
    (400), not an internal failure. The message contains "not found" and it is
    still a 400 — prose decides nothing.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        "update_member",
        _put_member,
        ValueError(
            "Cannot update immutable columns: points_balance (not found)"
        ),
    )

    assert resp.status_code == 400, resp.text
    assert "immutable columns" in resp.json()["detail"]


@pytest.mark.parametrize(
    ("label", "method_name", "call"),
    [e for e in _ENDPOINTS if e[1] != "update_member"],
)
def test_typed_only_handler_turns_a_validation_error_into_a_500(
    client, auth_headers, fake_member_id, label, method_name, call
) -> None:
    """A pydantic ``ValidationError`` is an INTERNAL failure -> 500.

    These five handlers' services raise only typed ``MembersError``s, so a
    blanket ``except ValueError`` arm could ONLY ever fire on our own bug —
    answering a malformed response model as a 4xx whose ``detail`` is a raw
    validation dump.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        method_name,
        call,
        _a_real_validation_error(),
    )

    assert resp.status_code == 500, f"{label}: {resp.text}"
    assert isinstance(resp.json()["detail"], str), label


def test_foreign_value_error_on_a_typed_only_handler_is_a_500(
    client, auth_headers, fake_member_id
) -> None:
    """The same rule for any other stray ``ValueError`` on those handlers.

    Nothing in ``has_payment_method``'s path raises an untyped ``ValueError``,
    so one arriving is our bug — and a wrong ``false`` here invites a stranger's
    card onto a member's account, so it must be a loud 500, never a quiet 4xx.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        "has_payment_method",
        _get_payment_method_status,
        ValueError("something odd happened deep in the stack"),
    )

    assert resp.status_code == 500, resp.text
    assert "has_payment_method" not in resp.json()


# ── the anti-regression pair, stated explicitly ─────────────────────────


def test_prose_no_longer_decides_the_status(
    client, auth_headers, fake_member_id
) -> None:
    """Both directions in one place: a 404 type whose message lacks "not found"
    still 404s, and every 400 type whose message CONTAINS it still 400s.
    Substring dispatch fails this test both ways."""

    def _status(exc: MembersError) -> int:
        return _call_with_service_error(
            client,
            auth_headers,
            fake_member_id,
            "has_payment_method",
            _get_payment_method_status,
            exc,
        ).status_code

    assert _status(MemberNotFoundError("Unknown member 123")) == 404
    for exc_type in _400_TYPES:
        assert _status(exc_type("Member not found — but still a 400")) == 400


# ── the member-DETAIL reads: the worst blanket-ValueError trap ──────────
#
# Both reads serve MembersBillingDetailService.get_member_billing_detail, the
# largest response model in the CRM. A blanket `except ValueError -> 404` there
# reports one bad field anywhere in that payload as a missing member, hiding a
# 500 that should page someone. They catch only MembersError.

_DETAIL_ENDPOINTS = (
    ("GET /members/{id}", lambda c, h, m: c.get(f"/api/v1/members/{m}", headers=h)),
    (
        "GET /members/{id}/billing",
        lambda c, h, m: c.get(f"/api/v1/members/{m}/billing", headers=h),
    ),
)


def _call_detail_with_service_error(client, headers, member_id, call, exc):
    """Issue ``call`` with the billing-detail service raising ``exc``."""
    detail_service = MagicMock()
    detail_service.get_member_billing_detail = AsyncMock(side_effect=exc)
    container = client.app.container
    container.members_billing_detail_service.override(detail_service)
    try:
        return call(client, headers, member_id)
    finally:
        container.members_billing_detail_service.reset_override()


@pytest.mark.parametrize(("label", "call"), _DETAIL_ENDPOINTS)
def test_detail_read_maps_member_not_found_to_404(
    client, auth_headers, fake_member_id, label, call
) -> None:
    """A genuinely missing member is a 404, off the TYPE: the message lacks
    "not found", so it 404s purely because ``MemberNotFoundError`` says so."""
    resp = _call_detail_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        call,
        MemberNotFoundError(_MSG_WITHOUT_THE_MAGIC_WORDS),
    )

    assert resp.status_code == 404, f"{label}: {resp.text}"
    assert resp.json()["detail"] == _MSG_WITHOUT_THE_MAGIC_WORDS, label


@pytest.mark.parametrize(("label", "call"), _DETAIL_ENDPOINTS)
def test_detail_read_turns_a_validation_error_into_a_500(
    client, auth_headers, fake_member_id, label, call
) -> None:
    """A broken detail payload is a logged 500, NOT "Member not found" — the
    regression the narrowed arm exists for."""
    resp = _call_detail_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        call,
        _a_real_validation_error(),
    )

    assert resp.status_code == 500, f"{label}: {resp.text}"
    assert isinstance(resp.json()["detail"], str), label
    assert "not found" not in resp.json()["detail"].lower(), label


@pytest.mark.parametrize(("label", "call"), _DETAIL_ENDPOINTS)
def test_detail_read_foreign_value_error_is_a_500(
    client, auth_headers, fake_member_id, label, call
) -> None:
    """Any other stray ``ValueError`` deep in the read is also a 500.

    The read takes one path parameter FastAPI already parsed as a UUID, so an
    untyped ``ValueError`` arriving here is our bug, not a bad request.
    """
    resp = _call_detail_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        call,
        ValueError("something odd happened deep in the grouper"),
    )

    assert resp.status_code == 500, f"{label}: {resp.text}"
