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
own ``status_code`` as a class attribute; the router reads the status off the
raised instance rather than re-deciding it, so a new subclass is wired to HTTP
the moment it declares that attribute.
``tests/members/test_members_error_mapping.py`` holds the whole
type -> status table and drives it through the live app with deliberately
message-hostile strings.

**There is no machine-readable ``code`` here, deliberately.** A sibling
``code`` beside ``detail`` is opt-in per domain (the root convention), and it
earns its keep only where a client must branch on a specific rejection —
``checkin``, whose kiosk switches on the code to pick its blocked-screen copy.
No CRM caller branches past the STATUS on a members rejection: every one of
them either shows ``detail`` as prose or reacts to 404-vs-400. A ``code`` here
would therefore be declared, test-locked and invisible — it cannot reach the
wire without the one global ``app.add_exception_handler`` formatter in
``src/main.py``, and adding that formatter for values nobody reads buys
nothing while making four strings part of the public contract forever. If a
client ever does need to branch, add the enum AND the formatter in the same
change; a half-wired code is the state this comment exists to prevent.

A members rejection therefore serializes as a plain-string ``detail`` and
nothing else, and each router arm maps ``exc.status_code`` itself.

All of them subclass ``ValueError`` so every pre-existing
``except ValueError`` — this router's own generic bad-input arm, the create
handler's, any other domain that calls a members service — keeps working
exactly as before (a 400 bad-request) rather than falling through to a 500.
That is what makes the typed hierarchy **additive** instead of a breaking
sweep: no caller has to know about it to keep behaving correctly.

Status table (owned here, applied by the router arms):

* ``MemberNotFoundError``                   -> 404
* ``MemberGymStripeAccountMissingError``    -> 400
* ``MemberStripeCustomerMissingError``      -> 400
* ``MemberNoUpdateFieldsError``             -> 400

The three 400s are bad-request on purpose, not 404s: the *member* exists in
every one of them: it is the billing configuration that is unusable (no
Connect account on the gym, no Stripe customer on the member) or the request
that is empty. Only a missing member row is a missing resource.
"""

from http import HTTPStatus


class MembersError(ValueError):
    """Base for every members-domain rejection of a caller's request.

    Subclasses ``ValueError`` deliberately — see the module docstring.

    Attributes:
        status_code: The HTTP status this rejection maps to. Subclasses
            override it; the base default is a 400 bad-request so a
            not-yet-classified subclass can never 500 a live request (the
            reflection test is what fails loudly instead).
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberNotFoundError(MembersError):
    """No member row for this id.

    404. This is the ONLY members condition that 404s — every other one
    below is a real member whose billing setup or request is unusable.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class MemberGymStripeAccountMissingError(MembersError):
    """The member's gym has no Stripe Connect account configured.

    400. The member exists; the gym cannot transact, so nothing about this
    member's card or invoices is readable or writable. Never answered as a
    benign empty/false — a caller gating on a payment method must not read
    "unknown" as "nothing on file".
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberStripeCustomerMissingError(MembersError):
    """The member row exists but carries no ``stripe_customer_id``.

    400. Every member is provisioned a Stripe customer at creation, so this
    is a broken invariant rather than a normal state — the operations that
    need one fail loudly instead of silently provisioning a second customer.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberNoUpdateFieldsError(MembersError):
    """An update request carried no fields to write.

    400.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
