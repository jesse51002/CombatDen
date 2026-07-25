"""The members domain's exception TYPE -> (HTTP status, ``code``) contract.

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
loop: a new ``MembersError`` subclass that nobody assigned a status/code to
fails here rather than silently inheriting the base's fallback.

**The wire shape today is a plain-string ``detail`` and nothing else.** The
``code`` column of the table below is locked at the TYPE level (the reflection
tests), not on the wire: emitting a sibling ``code`` needs the one global
``app.add_exception_handler`` formatter in ``src/main.py``, which is a pending
decision. ``test_the_wire_shape_is_status_plus_detail_only`` is the tripwire —
when that handler is registered, it is the test that must change (to assert
the sibling ``code`` is present), and every router arm collapses to a bare
``raise``. Nothing else about this file changes.

**Two blanket-``except ValueError`` traps are locked here too.** pydantic's
``ValidationError`` subclasses ``ValueError``, so a blanket arm on a handler
whose service raises no bad-input ``ValueError`` can only ever fire on an
internal failure — answering a broken response model with a 4xx carrying a raw
validation dump instead of a logged 500. The handlers whose services raise
only typed errors now have no such arm; ``PUT /members/{id}`` keeps one
because the shared ``validate_mutable_columns`` guard really does raise a
plain ``ValueError`` for an immutable column. Both directions are asserted.
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
    MembersErrorCode,
    MemberStripeCustomerMissingError,
)
from src.members.schema.members_billing_schema import (
    MembersBillingProfileResponse,
)

# Deliberately message-hostile fixtures: the 404 type's message avoids the
# words the old dispatch keyed on, and every 400 type's message contains them.
_MSG_WITHOUT_THE_MAGIC_WORDS = "no such member at this gym"
_MSG_WITH_THE_MAGIC_WORDS = "the thing was not found, and yet this is a 400"

# The whole public contract, in one table. Read it as: this type, that status,
# that stable code. Renaming a code is a BREAKING change for any client that
# switches on it — add a new one instead.
_TYPE_TO_CONTRACT: tuple[tuple[type[MembersError], int, MembersErrorCode], ...] = (
    (MemberNotFoundError, 404, MembersErrorCode.member_not_found),
    (
        MemberGymStripeAccountMissingError,
        400,
        MembersErrorCode.gym_stripe_account_missing,
    ),
    (
        MemberStripeCustomerMissingError,
        400,
        MembersErrorCode.member_stripe_customer_missing,
    ),
    (MemberNoUpdateFieldsError, 400, MembersErrorCode.no_update_fields),
)

_TYPE_TO_STATUS: tuple[tuple[type[MembersError], int], ...] = tuple(
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
        assert own["code"] is not MembersErrorCode.members_error, (
            f"{exc_type.__name__} reuses the base fallback code"
        )


def test_type_attributes_match_the_contract_table() -> None:
    """The type itself is the single source of truth the routers read, so the
    class attributes and the table must agree exactly."""
    for exc_type, expected_status, expected_code in _TYPE_TO_CONTRACT:
        assert exc_type.status_code == expected_status, exc_type.__name__
        assert exc_type.code is expected_code, exc_type.__name__


def test_codes_are_unique() -> None:
    """Two types sharing a code would make the discriminator ambiguous."""
    codes = [code for _, _, code in _TYPE_TO_CONTRACT]
    assert len(set(codes)) == len(codes)


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
@pytest.mark.parametrize(
    ("exc_type", "expected", "expected_code"), _TYPE_TO_CONTRACT
)
def test_endpoint_maps_error_type_to_status(
    client,
    auth_headers,
    fake_member_id,
    label,
    method_name,
    call,
    exc_type,
    expected,
    expected_code,
) -> None:
    """Every converted handler maps the service's exception TYPE to its
    status — with a message that would have pushed the OPPOSITE way under the
    old substring dispatch.

    ``expected_code`` rides along from the same table so the parametrization
    can't drift from the contract; the code is asserted at the type level
    (``test_type_attributes_match_the_contract_table``) because it is not on
    the wire yet — see the module docstring.
    """
    assert exc_type.code is expected_code

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
    """TRIPWIRE for the pending global handler.

    A typed rejection serializes today as a plain-string ``detail`` and no
    sibling ``code``: putting the code on the wire needs the one global
    ``app.add_exception_handler`` formatter in ``src/main.py`` (the CRM reads
    ``data['detail']`` only when it is a String, so the code can never be
    nested inside it, and no router-local shape can add a sibling key without
    duplicating the formatter at six call sites).

    When that handler is registered, THIS is the test to change: assert
    ``body["code"] == MembersErrorCode.member_not_found.value`` instead. It
    failing is the signal the wire shape moved — which is exactly what a
    client switching on ``code`` needs to know.
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
