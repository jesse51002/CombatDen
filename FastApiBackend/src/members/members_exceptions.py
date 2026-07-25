"""Custom exceptions for the members domain.

The service layer raises these; the HTTP status comes off the exception
**type**, never off the message text. That is the whole point of this module:
before it existed every member-management handler decided 404-vs-400 with
``if "not found" in str(exc).lower()``, so the *prose* of a message was part
of the public API. Rewording ``f"Member {member_id} not found"`` to
"Unknown member <id>" — a pure copy edit, invisible to any reviewer reading
the router — flipped ``GET /members/{id}/payment-method-status`` from its
documented 404 to a 400, and no test could catch it structurally (the tests
hand-fed a message that already contained the magic words). Meanwhile the
sibling ``"Gym … has no Stripe account configured"`` landed on 400 only by
the accident of not containing them.

**The type is the single source of truth.** Each concrete class declares its
own ``status_code`` and ``code`` as class attributes; the router reads the
status off the raised instance rather than re-deciding it, so a new subclass
is wired to HTTP the moment it declares its two attributes.
``tests/members/test_members_error_mapping.py`` holds the whole
type -> (status, code) table and drives it through the live app with
deliberately message-hostile strings.

``code`` is the stable machine-readable discriminator a client switches on,
and it is declared here so its values are locked before they ship. **It is
not on the wire yet:** serializing a sibling ``code`` beside ``detail``
requires the one global ``app.add_exception_handler`` formatter in
``src/main.py`` (the ``_handle_checkin_error`` template) — the CRM reads
``data['detail']`` only when it is a plain String, so the code can never be
nested inside ``detail``, and no router-local shape can add a sibling key
without duplicating the formatter at every call site. Registering that
handler is a pending decision; until it lands, clients branch on the status
and read ``detail``. When it lands, every router arm below collapses to a
bare ``raise`` and nothing else changes.

**Codes are part of the public contract.** Renaming one is a breaking change
for every client that switches on it — add a new code rather than
repurposing an existing one.

All of them subclass ``ValueError`` so every pre-existing
``except ValueError`` — this router's own generic bad-input arm, the create
handler's, any other domain that calls a members service — keeps working
exactly as before (a 400 bad-request) rather than falling through to a 500.
That is what makes the typed hierarchy **additive** instead of a breaking
sweep: no caller has to know about it to keep behaving correctly.

Status + code table (owned here, applied by the router arms):

* ``MemberNotFoundError``                  -> 404 ``member_not_found``
* ``MemberGymStripeAccountMissingError``    -> 400 ``gym_stripe_account_missing``
* ``MemberStripeCustomerMissingError``      -> 400 ``member_stripe_customer_missing``
* ``MemberNoUpdateFieldsError``             -> 400 ``no_update_fields``

The three 400s are bad-request on purpose, not 404s: the *member* exists in
every one of them: it is the billing configuration that is unusable (no
Connect account on the gym, no Stripe customer on the member) or the request
that is empty. Only a missing member row is a missing resource.
"""

from enum import StrEnum
from http import HTTPStatus


class MembersErrorCode(StrEnum):
    """Stable machine-readable discriminators for member rejections.

    **Public API contract.** A value is never renamed or repurposed once a
    client switches on it — add a new member instead.

    ``members_error`` is the base class's fallback only; no concrete
    exception uses it (``tests/members/test_members_error_mapping.py``
    enforces that every concrete subclass declares its own).
    """

    members_error = "members_error"
    member_not_found = "member_not_found"
    gym_stripe_account_missing = "gym_stripe_account_missing"
    member_stripe_customer_missing = "member_stripe_customer_missing"
    no_update_fields = "no_update_fields"


class MembersError(ValueError):
    """Base for every members-domain rejection of a caller's request.

    Subclasses ``ValueError`` deliberately — see the module docstring.

    Attributes:
        status_code: The HTTP status this rejection maps to. Subclasses
            override it; the base default is a 400 bad-request so a
            not-yet-classified subclass can never 500 a live request (the
            reflection test is what fails loudly instead).
        code: The stable machine-readable discriminator. Every concrete
            subclass declares its own.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: MembersErrorCode = MembersErrorCode.members_error


class MemberNotFoundError(MembersError):
    """No member row for this id.

    404 / ``member_not_found``. This is the ONLY members condition that
    404s — every other one below is a real member whose billing setup or
    request is unusable.
    """

    status_code: int = HTTPStatus.NOT_FOUND
    code: MembersErrorCode = MembersErrorCode.member_not_found


class MemberGymStripeAccountMissingError(MembersError):
    """The member's gym has no Stripe Connect account configured.

    400 / ``gym_stripe_account_missing``. The member exists; the gym cannot
    transact, so nothing about this member's card or invoices is readable or
    writable. Never answered as a benign empty/false — a caller gating on a
    payment method must not read "unknown" as "nothing on file".
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: MembersErrorCode = MembersErrorCode.gym_stripe_account_missing


class MemberStripeCustomerMissingError(MembersError):
    """The member row exists but carries no ``stripe_customer_id``.

    400 / ``member_stripe_customer_missing``. Every member is provisioned a
    Stripe customer at creation, so this is a broken invariant rather than a
    normal state — the operations that need one fail loudly instead of
    silently provisioning a second customer.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: MembersErrorCode = MembersErrorCode.member_stripe_customer_missing


class MemberNoUpdateFieldsError(MembersError):
    """An update request carried no fields to write.

    400 / ``no_update_fields``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: MembersErrorCode = MembersErrorCode.no_update_fields
