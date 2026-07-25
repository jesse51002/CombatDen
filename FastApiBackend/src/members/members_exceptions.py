"""Custom exceptions for the members domain.

**The type is the single source of truth** for the HTTP status — never the
message text. Each concrete class declares its own ``status_code`` and the
router reads it off the raised instance. Status-by-prose
(``if "not found" in str(exc)``) makes a copy edit a silent API change; this
module exists to prevent that, and
``tests/members/test_members_error_mapping.py`` drives the whole
type -> status table through the live app with message-hostile strings.

**There is deliberately no machine-readable ``code`` here.** A sibling
``code`` is opt-in per domain, and no CRM caller branches past the STATUS on
a members rejection — declaring one would test-lock four strings that cannot
even reach the wire without a global handler in ``src/main.py``. If a client
ever needs to branch, add the enum AND the handler in the same change.

All subclass ``ValueError`` so every pre-existing ``except ValueError`` keeps
landing on a 400 rather than a 500, which is what makes the hierarchy
additive rather than a breaking sweep.
"""

from http import HTTPStatus


class MembersError(ValueError):
    """Base for every members-domain rejection of a caller's request.

    Subclasses ``ValueError`` deliberately — see the module docstring. The
    400 default is a safe fallback so a subclass that forgets to declare its
    own can never 500 a live request; the reflection test fails instead.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberNotFoundError(MembersError):
    """No member row for this id. The ONLY members condition that 404s."""

    status_code: int = HTTPStatus.NOT_FOUND


class MemberGymStripeAccountMissingError(MembersError):
    """The member's gym has no Stripe Connect account configured.

    Never answered as a benign empty/false — a caller gating on a payment
    method must not read "unknown" as "nothing on file".
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberStripeCustomerMissingError(MembersError):
    """The member row exists but carries no ``stripe_customer_id``.

    A broken invariant, not a normal state (creation provisions one), so the
    ops that need it fail loudly rather than provision a second customer.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class MemberNoUpdateFieldsError(MembersError):
    """An update request carried no fields to write."""

    status_code: int = HTTPStatus.BAD_REQUEST
