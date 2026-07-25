"""Custom exceptions for the waivers domain.

The service layer raises these; the HTTP status comes off the exception
**type**, never off the message text. Before this module existed every waiver
handler decided its status with ``if "not found" in str(exc).lower()`` — plus,
on the signing paths, ``if "reload" in str(exc).lower()`` for the 409 — so the
*prose* of a message was part of the public API. Rewording
``"Waiver was updated since it was displayed — reload and sign the current
version"`` to drop the word "reload" would have silently turned the
version-lock conflict from a 409 into a 400, and no test could have caught it
structurally. The ``"reload"`` match was the worst of the two: nothing about
that word says "conflict", so the coupling was invisible to a reader of either
side.

**The type is the single source of truth.** Each concrete class declares its
own ``status_code`` as a class attribute; the router reads the status off the
raised instance rather than re-deciding it, so a new subclass is wired to HTTP
the moment it declares that attribute.
``tests/waivers/test_waivers_error_mapping.py`` holds the whole type -> status
table and drives it through the live app with deliberately message-hostile
strings.

**There is no machine-readable ``code`` here, deliberately** — the same call
as ``members``. A sibling ``code`` beside ``detail`` is opt-in per domain and
earns its keep only where a client must branch on a specific rejection
(``checkin``, whose kiosk switches on it to pick its blocked-screen copy). No
CRM caller branches past the STATUS on a waiver rejection: the sign dialogs
react to 409-vs-404-vs-400 and render ``detail`` as prose. A ``code`` here
would be declared, test-locked and invisible — it cannot reach the wire
without the one global ``app.add_exception_handler`` formatter in
``src/main.py``. If a client ever needs to branch, add the enum AND the
formatter in the same change.

The base subclasses ``ValueError`` because waivers is an **input-validation**
domain, not a money / external-system one: an unmapped waiver rejection should
land as a 400 bad-request, not a 500. That also keeps the hierarchy
**additive** — every pre-existing ``except ValueError`` arm (this router's own,
and the members router's linked-account arms, whose other errors still come
from ``src/memberships/``) keeps behaving exactly as before.

Status table (owned here, applied by the router arms):

* ``WaiverNotFoundError``               -> 404
* ``WaiverVersionNotFoundError``        -> 404
* ``WaiverNoCurrentVersionError``       -> 400
* ``WaiverVersionStaleError``           -> 409
* ``WaiverSignerNotInGymError``         -> 404
* ``WaiverPayerAuthMissingError``       -> 404
* ``WaiverPayerAuthNotArchivableError`` -> 400

Two of those statuses are inherited from the prose dispatch rather than chosen
here, and both are recorded so a future reader does not mistake an accident
for a decision:

* ``WaiverNoCurrentVersionError`` is a **400** because that is what
  ``PUT /api/v1/waivers/`` answered before: the message "Waiver has no current
  version" does not contain "not found", so it fell through to the bad-request
  arm. Read as "you asked to flip the re-sign flag on a waiver that has no
  version to flip it on", 400 is arguable; read as "the resource you addressed
  is missing", 404 is arguable. Statuses are a contract, so the refactor
  preserved it instead of improving it — changing it is a separate call.
* ``WaiverPayerAuthMissingError`` is a **404** everywhere now, which is what
  ``GET /members/{id}/authorized-payer-waiver`` already documented and
  returned. The SAME raise reached ``PUT /members/{id}/link`` as a **400**,
  purely because "No payer-auth waiver for member …'s gym" happens not to
  contain "not found" — two statuses for one condition, decided by which route
  the caller happened to hit. One type cannot keep both; 404 wins because a
  gym with no payer-auth agreement is a missing resource, and because it is
  the status the read path documents.
"""

from http import HTTPStatus


class WaiversError(ValueError):
    """Base for every waivers-domain rejection of a caller's request.

    Subclasses ``ValueError`` deliberately — see the module docstring.

    Attributes:
        status_code: The HTTP status this rejection maps to. Subclasses
            override it; the base default is a 400 bad-request so a
            not-yet-classified subclass can never 500 a live request (the
            reflection test is what fails loudly instead).
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class WaiverNotFoundError(WaiversError):
    """No non-archived waiver with this id in this gym.

    404. Covers a missing row and an archived (``is_deleted``) one alike: an
    archived waiver is invisible to every read and unsignable, so telling the
    caller it exists-but-is-hidden would leak catalog state for no benefit.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverVersionNotFoundError(WaiversError):
    """A version row the request named, or the one the waiver points at, is
    gone.

    404. Raised when a version-scoped write (an in-place body edit, a
    ``requires_resign`` flip) matches no row, and when a read cannot resolve
    the waiver's ``current_version_id`` to a row — in both cases the version
    the caller addressed does not exist.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverNoCurrentVersionError(WaiversError):
    """The waiver carries no ``current_version_id`` at all.

    400 — preserved from the prose dispatch, not chosen; see the module
    docstring. Distinct from :class:`WaiverVersionNotFoundError`, which is a
    version that was addressed and is missing.
    """

    status_code: int = HTTPStatus.BAD_REQUEST


class WaiverVersionStaleError(WaiversError):
    """The echoed ``waiver_version_id`` is not the waiver's current version.

    409. The signer was shown a version that has since been superseded, so
    signing it would freeze the WRONG text into the legal record. A conflict
    rather than a bad request: the client's input was correct when it was
    fetched, and the fix is to reload and re-sign, not to correct a field.
    """

    status_code: int = HTTPStatus.CONFLICT


class WaiverSignerNotInGymError(WaiversError):
    """The member being signed for does not belong to the waiver's gym.

    404. Surfaced from the signature INSERT's ``(member_id, gym_id)`` composite
    FK — the waiver, its version and the operator are all validated before the
    write, so that FK is the only one left to trip.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverPayerAuthMissingError(WaiversError):
    """The member's gym has no ``payer_auth`` waiver.

    404 — see the module docstring for why this is 404 on BOTH the read and
    the link path now. A gym is seeded one at creation, so this is a broken
    invariant rather than a normal state, and the authorize-payer gate cannot
    proceed without a document to sign.
    """

    status_code: int = HTTPStatus.NOT_FOUND


class WaiverPayerAuthNotArchivableError(WaiversError):
    """Someone tried to archive the gym's ``payer_auth`` waiver.

    400. The gym has exactly one authorized-payer agreement and the link flow
    always needs it, so it is never archivable — a refused operation on an
    existing resource, not a missing one. The DB trigger only blocks the
    client roles; the backend runs at service role, so this service-level
    guard is the one that actually protects the API path.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
