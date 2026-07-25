"""The members domain's exception TYPE -> HTTP status contract.

This is the regression the router could not previously catch. Six
member-management handlers picked their status with
``if "not found" in str(exc).lower()``, so the *prose* of a message decided
the public API's status code. Rewording ``f"Member {member_id} not found"`` to
"Unknown member <id>" — a pure copy edit — flipped
``GET /members/{id}/payment-method-status`` from its documented 404 to a 400,
and the only test covering it hand-fed a message that already contained the
magic words, so it stayed green. The sibling
``"Gym … has no Stripe account configured"`` landed on 400 only by the
accident of NOT containing them.

Every test here drives the mapping through an exception TYPE with a message
chosen to prove the message is irrelevant:

* the 404 type carries a message with NO "not found" in it — under the old
  substring dispatch it would have been a 400;
* every 400 type carries a message that DOES contain "not found" — under the
  old substring dispatch each would have been a 404.

So these tests still pass when somebody rewords a message, and fail the moment
somebody remaps a type. ``test_every_members_error_type_is_mapped`` closes the
loop: a new ``MembersError`` subclass that nobody assigned a status to fails
here rather than silently inheriting the base's fallback.

**The wire shape is a plain-string ``detail`` and nothing else, by
decision.** ``members`` declares no machine-readable ``code``: a sibling
``code`` is opt-in per domain and earns its keep only where a client branches
on a specific rejection (``checkin``, whose kiosk picks copy from it). No CRM
caller branches past the STATUS here, so a code would be declared, test-locked
and invisible — it cannot even reach the wire without the one global
``app.add_exception_handler`` formatter in ``src/main.py``.
``test_the_wire_shape_is_status_plus_detail_only`` pins that shape: if a code
ever IS needed, the enum and the formatter land together and that test is
where the change becomes visible.

**Three blanket-``except ValueError`` traps are locked here too.** pydantic's
``ValidationError`` subclasses ``ValueError``, so a blanket arm on a handler
whose service raises no bad-input ``ValueError`` can only ever fire on an
internal failure — answering a broken response model with a 4xx carrying a raw
validation dump instead of a logged 500. The handlers whose services raise
only typed errors now have no such arm; ``PUT /members/{id}`` keeps one
because the shared ``validate_mutable_columns`` guard really does raise a
plain ``ValueError`` for an immutable column. Both directions are asserted.

The two member-DETAIL reads (``GET /members/{id}`` and
``GET /members/{id}/billing``) are the worst case of that trap and get their
own section at the bottom: they served the largest response model in the CRM
behind a blanket ``except ValueError -> 404 "Member not found"``, so ANY field
of that payload going out of shape reported a member who plainly exists as
missing, and the 500 that should have paged someone was indistinguishable from
a mistyped id.
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

# The whole public contract, in one table: this type, that status. There is no
# machine-readable ``code`` column — see the module docstring for why members
# deliberately has none.
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
    """A genuine pydantic ``ValidationError`` — which IS a ``ValueError``.

    Used to prove a blanket ``except ValueError`` arm would misclassify an
    internal serialization failure as a 4xx.
    """
    try:
        MembersBillingProfileResponse.model_validate({})
    except ValidationError as exc:
        return exc
    raise AssertionError("empty MembersBillingProfileResponse unexpectedly valid")


# ── the endpoints whose status is decided by the exception type ─────────
#
# Each entry: (label, the management-service method the handler awaits, a
# callable issuing the request). Every one of these six handlers used to pick
# 404-vs-400 by matching words in the message.


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
    """The base is a ``ValueError`` subclass on purpose: every pre-existing
    ``except ValueError`` (the create handler's bad-input arm, the linked-
    account handlers, any other domain calling a members service) keeps
    working unchanged, so the typed hierarchy is additive rather than a
    breaking sweep."""
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
    """Every concrete ``MembersError`` in the module carries an explicit
    status in the table above. Adding a new one without deciding it fails
    HERE, instead of silently defaulting in production."""
    assert _concrete_error_types() == {
        exc_type for exc_type, _ in _TYPE_TO_STATUS
    }


def test_every_type_declares_its_own_status_code() -> None:
    """A new subclass must DECLARE ``status_code``, never inherit it.

    The base carries a safe fallback so a not-yet-classified subclass can't
    500 a live request — this test is what makes forgetting it loud. It
    reads each class's OWN ``vars()``, so an inherited value fails.
    """
    for exc_type in _concrete_error_types():
        own = vars(exc_type)
        assert "status_code" in own, f"{exc_type.__name__} inherits status_code"


def test_no_type_declares_a_machine_readable_code() -> None:
    """``members`` deliberately has no ``code`` machinery.

    A sibling ``code`` is opt-in per domain and only earns its keep where a
    client branches on a specific rejection. Nothing does here, and a code
    cannot even reach the wire without the global formatter in
    ``src/main.py`` — so declaring one would test-lock four strings into the
    public contract while staying invisible to every caller. That
    half-wired state is what this asserts against: if a code is ever needed,
    the enum and the formatter land together, and this test plus
    ``test_the_wire_shape_is_status_plus_detail_only`` are where the
    decision has to be made explicitly.
    """
    assert not hasattr(members_exceptions, "MembersErrorCode")
    for exc_type in _concrete_error_types() | {MembersError}:
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

    Documented here because it is the whole reason the five typed-only
    handlers no longer catch bare ``ValueError``: an internal serialization
    failure must be a logged 500, not a 4xx carrying a raw validation dump
    as ``detail``.
    """
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
    """Every converted handler maps the service's exception TYPE to its
    status — with a message that would have pushed the OPPOSITE way under the
    old substring dispatch.
    """
    resp = _call_with_service_error(
        client,
        auth_headers,
        fake_member_id,
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
    client, auth_headers, fake_member_id
) -> None:
    """The whole wire shape: a status and a plain-string ``detail``.

    Asserted as an EQUALITY on the body, not a subset, so nothing can quietly
    grow a second key. ``members`` has no machine-readable ``code`` by
    decision (see the module docstring): a sibling key would need the one
    global ``app.add_exception_handler`` formatter in ``src/main.py``, because
    the CRM reads ``data['detail']`` only when it is a String — so the code
    could never be nested inside ``detail``, and no router-local shape can add
    a sibling without duplicating the formatter at every call site.

    If a client ever does need to branch on a code, THIS is the test that has
    to change, in the same commit as the enum and the formatter. It failing is
    the signal the wire shape moved.
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

    Its service really does raise a plain ``ValueError``: the shared,
    domain-agnostic ``validate_mutable_columns`` guard rejects an immutable
    column that way, and that is a caller error (400), not an internal
    failure. Note the message contains "not found" and it is still a 400 —
    the prose no longer decides anything.
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
    blanket ``except ValueError`` arm could ONLY ever fire on an internal
    failure — and ``ValidationError`` subclasses ``ValueError``, so under the
    old arms a malformed response model came back as a 400 (or, if its dump
    happened to contain the words "not found", a 404) whose ``detail`` was a
    raw validation dump. Each is a logged 500 now.
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

    Nothing in ``has_payment_method``'s path raises an untyped bad-input
    ``ValueError``, so one arriving here is a bug on our side, not a bad
    request — and this endpoint's failure mode is asymmetric (a wrong
    ``false`` invites a stranger's card onto a member's account), so an
    unclassifiable failure must be a loud 500, never a quiet 4xx.
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
    """Both directions of the old bug, in one place.

    A 404 type whose message lacks "not found" must still 404, and every 400
    type whose message CONTAINS "not found" must still 400. Under the
    substring dispatch this test failed in both directions — which is exactly
    how a reworded message could have moved ``payment-method-status`` off its
    documented 404.
    """

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
# GET /members/{id} and GET /members/{id}/billing both serve
# MembersBillingDetailService.get_member_billing_detail — the largest response
# model in the CRM (memberships grouped by plan, authorized payers, who-pays-
# for-whom, payment history, rewards, pending redemptions, rank, card). Both
# used to answer ANY ValueError with 404 "Member not found". pydantic's
# ValidationError IS a ValueError, so one bad field anywhere in that payload
# reported a member who plainly exists as missing: the CRM showed "not found",
# the caller re-checked the id, and the 500 that should have paged someone was
# never visible. They now catch only MembersError.

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
    """A genuinely missing member is still a 404 — now off the TYPE.

    The message deliberately lacks "not found", so this would have been a 400
    under a substring dispatch and is a 404 purely because
    ``MemberNotFoundError`` says so.
    """
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
    """A broken detail payload is a logged 500, NOT "Member not found".

    This is the regression the narrowing exists for. Before it, a
    ``ValidationError`` on this read — the single most complex response model
    in the API — was reported to staff as a missing member.
    """
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

    Nothing on this path raises an untyped bad-input ``ValueError`` — the read
    takes a single path parameter FastAPI has already parsed as a UUID — so one
    arriving here is a bug on our side, not a bad request.
    """
    resp = _call_detail_with_service_error(
        client,
        auth_headers,
        fake_member_id,
        call,
        ValueError("something odd happened deep in the grouper"),
    )

    assert resp.status_code == 500, f"{label}: {resp.text}"
