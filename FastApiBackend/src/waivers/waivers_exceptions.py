"""Custom exceptions for the waivers domain.

**The type is the single source of truth** for the HTTP status — never the
message text. Each concrete class declares its own ``status_code`` and the
router reads it off the raised instance.
``tests/waivers/test_waivers_error_mapping.py`` drives the whole
type -> status table through the live app with message-hostile strings.

This domain is the cautionary tale: the 409 hung off
``if "reload" in str(exc).lower()``, so dropping that word from a
signer-facing message would have demoted a version-lock conflict to a 400 —
inviting the client to re-submit the same stale version.

**There is deliberately no machine-readable ``code`` here** (same call as
``members``): no CRM caller branches past the STATUS, and a code cannot reach
the wire without a global handler in ``src/main.py``. If one is ever needed,
add the enum AND the handler in the same change.

The base subclasses ``ValueError`` because waivers is an input-validation
domain: an unmapped rejection lands as a 400, not a 500, which keeps the
hierarchy additive for every pre-existing ``except ValueError`` arm.

Two statuses are **inherited rather than chosen**, recorded so nobody
mistakes an accident for a decision: ``WaiverNoCurrentVersionError`` (400 —
404 is equally arguable) and ``WaiverPayerAuthMissingError`` (404 — one raise
that answered both, and one type cannot keep both). A status is a contract, so
changing either is a separate call.
"""

from http import HTTPStatus


class WaiversError(ValueError):
    """Base for every waivers-domain rejection of a caller's request.

    Subclasses ``ValueError`` deliberately — see the module docstring. The
    400 default is a safe fallback so a subclass that forgets to declare its
    own can never 500 a live request; the reflection test fails instead.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class WaiverNotFoundError(WaiversError):
    """No non-archived waiver with this id in this gym.

    Covers a missing row and an archived one alike — an archived waiver is
    invisible to every read and unsignable, so distinguishing the two would
    leak catalog state for no benefit.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverVersionNotFoundError(WaiversError):
    """The version the request named, or the one the waiver points at, is gone."""

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverNoCurrentVersionError(WaiversError):
    """The waiver carries no ``current_version_id`` at all.

    Distinct from :class:`WaiverVersionNotFoundError` (a version that WAS
    addressed and is missing). The 400 is inherited, not chosen — see the
    module docstring.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class WaiverVersionStaleError(WaiversError):
    """The echoed ``waiver_version_id`` is not the waiver's current version.

    Signing it would freeze the WRONG text into the legal record. A 409, not a
    400: the input was correct when fetched, so the fix is to reload and
    re-sign, not to correct a field.
    """

    status_code: int = HTTPStatus.CONFLICT


class WaiverSignerNotInGymError(WaiversError):
    """The member being signed for does not belong to the waiver's gym.

    Surfaced from the signature INSERT's ``(member_id, gym_id)`` composite FK
    — everything else is validated before the write, so it is the only one
    left to trip.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverPayerAuthMissingError(WaiversError):
    """The member's gym has no ``payer_auth`` waiver.

    A gym is seeded one at creation, so this is a broken invariant rather than
    a normal state — the authorize-payer gate cannot proceed without a
    document to sign.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverPayerAuthNotArchivableError(WaiversError):
    """Someone tried to archive the gym's ``payer_auth`` waiver.

    Never archivable — the link flow always needs it. The DB trigger only
    blocks the client roles; the backend runs at service role, so THIS guard
    is the one that actually protects the API path.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
