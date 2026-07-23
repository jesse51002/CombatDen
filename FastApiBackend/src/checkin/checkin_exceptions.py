"""Custom exceptions for the checkin domain.

The service layer raises these; the HTTP status AND the machine-readable
``code`` both come off the exception **type**, never off the message text.
That is the whole point of this module: before it existed the router decided
404-vs-400 with ``if "not found" in str(exc).lower()``, so rewording a message
silently changed the public API's status code and no test could catch it
structurally. Every mapping below is now locked to a type, and the router
tests assert the type -> (status, code) triple.

**The type is the single source of truth.** Each concrete class declares its
own ``status_code`` and ``code`` as class attributes, and the single global
handler in ``src/main.py`` (``_handle_checkin_error``) reads both off the
raised instance. Routers never re-decide either one — they only re-raise, so
a new subclass is wired to HTTP the moment it declares its two attributes.

The wire shape is a **sibling** ``code`` key beside a plain-string
``detail``::

    {"detail": "Class is not active", "code": "class_inactive"}

``detail`` MUST stay a plain string: the CRM's
``lib/core/network/api_client.dart`` ``_extractDetail`` only reads
``data['detail']`` when it is a String, and the member-detail bloc renders
``(e.detail ?? e.message)`` — nesting the code INSIDE ``detail`` would
silently degrade every real error message to "Server error 400: Bad Request".
``code`` is the stable discriminator clients switch on; the prose is for
humans and may be reworded freely.

**Codes are part of the public contract.** Renaming one is a breaking change
for every client that switches on it (today: the CRM kiosk's blocked-screen
copy). Add a new code rather than repurposing an existing one.

All of them subclass ``ValueError`` so the routers' generic
``except ValueError`` still catches an unmapped domain error exactly as
before (a 400 bad-request) rather than falling through to a 500. That keeps
every existing handler — including the per-member ``except Exception``
isolation in ``BatchCheckinService`` — working unchanged.

Status + code table (owned here, applied by the one global handler):

* ``CheckinClassNotFoundError``        -> 404 ``class_not_found``
* ``CheckinClassDeletedError``         -> 400 ``class_deleted``
* ``CheckinClassInactiveError``        -> 400 ``class_inactive``
* ``CheckinOccurrenceNotFoundError``   -> 400 ``occurrence_not_found``
* ``CheckinOccurrenceCancelledError``  -> 400 ``occurrence_cancelled``
* ``CheckinNotOpenYetError``           -> 400 ``checkin_not_open``
* ``CheckinClassFullError``            -> 400 ``class_full``

``CheckinOccurrenceNotFoundError`` maps to **400, not 404, on purpose**: the
occurrence is computed rather than stored, so "that slot is not an occurrence
of this class" is a bad address, not a missing resource — and both endpoints'
OpenAPI ``responses`` have documented it as ``400 Not a valid occurrence on
that date`` since they shipped. Changing it would be a contract break.
"""

from enum import StrEnum
from http import HTTPStatus


class CheckinErrorCode(StrEnum):
    """Stable machine-readable discriminators for check-in rejections.

    **Public API contract.** Clients (the CRM kiosk) switch on these to pick
    their own copy, so a value is never renamed or repurposed — add a new
    member instead.

    ``checkin_error`` is the base class's fallback only; no concrete
    exception uses it (``tests/checkin/test_checkin_error_mapping.py``
    enforces that every concrete subclass declares its own).
    """

    checkin_error = "checkin_error"
    class_not_found = "class_not_found"
    class_deleted = "class_deleted"
    class_inactive = "class_inactive"
    occurrence_not_found = "occurrence_not_found"
    occurrence_cancelled = "occurrence_cancelled"
    checkin_not_open = "checkin_not_open"
    class_full = "class_full"


class CheckinError(ValueError):
    """Base for every check-in / sign-up domain rejection.

    Subclasses ``ValueError`` deliberately — see the module docstring.

    Attributes:
        status_code: The HTTP status this rejection maps to. Subclasses
            override it; the base default is a 400 bad-request so a
            not-yet-classified subclass can never 500 in production (the
            reflection test is what fails loudly instead).
        code: The stable machine-readable discriminator emitted as a sibling
            of ``detail``. Every concrete subclass declares its own.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.checkin_error


class CheckinClassNotFoundError(CheckinError):
    """No such class for this gym (or the class row is gone).

    404 / ``class_not_found``. This is the ONLY check-in condition that 404s.
    """

    status_code: int = HTTPStatus.NOT_FOUND
    code: CheckinErrorCode = CheckinErrorCode.class_not_found


class CheckinClassDeletedError(CheckinError):
    """The class exists but is soft-deleted (``is_deleted``).

    400 / ``class_deleted``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_deleted


class CheckinClassInactiveError(CheckinError):
    """The class exists but is paused (``is_active`` false).

    400 / ``class_inactive``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_inactive


class CheckinOccurrenceNotFoundError(CheckinError):
    """The addressed ``(occurrence_date, occurrence_time)`` slot is not a real
    occurrence of this class.

    400 / ``occurrence_not_found`` (not 404 — see the module docstring:
    occurrences are computed, and 400 is the documented contract).
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.occurrence_not_found


class CheckinOccurrenceCancelledError(CheckinError):
    """The slot IS an occurrence of the class but that day is cancelled.

    Only the sign-up path can raise this: it resolves with
    ``include_cancelled=True`` so a cancelled day and a non-occurrence slot
    get distinct messages. The check-in path drops cancelled occurrences
    during resolution, so there it surfaces as
    ``CheckinOccurrenceNotFoundError``. 400 / ``occurrence_cancelled``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.occurrence_cancelled


class CheckinNotOpenYetError(CheckinError):
    """The occurrence starts further out than the check-in open window.

    400 / ``checkin_not_open``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.checkin_not_open


class CheckinClassFullError(CheckinError):
    """The occurrence is at its effective ``max_capacity``.

    Counted as the DISTINCT signed-up-or-attended union for the exact slot, so
    a member already counted never blocks on their own presence.
    400 / ``class_full``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_full
