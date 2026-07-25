"""Custom exceptions for the checkin domain.

**The type is the single source of truth** for both the HTTP status and the
machine-readable ``code`` — never the message text. Each concrete class
declares ``status_code`` + ``code``; the one global handler in ``src/main.py``
(``_handle_checkin_error``) reads both off the instance and routers only
re-raise. Status-by-prose (``if "not found" in str(exc)``) makes a copy edit a
silent API change, which is what this module exists to prevent.

Wire shape is a **sibling** ``code`` beside a plain-string ``detail``::

    {"detail": "Class is not active", "code": "class_inactive"}

``detail`` MUST stay a plain string — the CRM's ``_extractDetail``
(``lib/core/network/api_client.dart``) only reads it when it is a String, so
nesting the code inside it degrades every message to "Server error 400".
Codes are public contract: add a new one, never rename or repurpose.

All subclass ``ValueError`` so an unmapped domain error still lands on an
existing ``except ValueError`` → 400 rather than falling through to a 500.
"""

from enum import StrEnum
from http import HTTPStatus


class CheckinErrorCode(StrEnum):
    """Stable machine-readable discriminators for check-in rejections.

    Public API contract — the CRM kiosk switches on these to pick its
    blocked-screen copy. ``checkin_error`` is the base's fallback only; no
    concrete exception uses it (the error-mapping test enforces that).
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

    Subclasses ``ValueError`` deliberately — see the module docstring. The
    base defaults are safe fallbacks so a subclass that forgets to declare
    its own can never 500 a live request; the reflection test fails instead.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.checkin_error


class CheckinClassNotFoundError(CheckinError):
    """No such class for this gym. The ONLY check-in condition that 404s."""

    status_code: int = HTTPStatus.NOT_FOUND
    code: CheckinErrorCode = CheckinErrorCode.class_not_found


class CheckinClassDeletedError(CheckinError):
    """The class exists but is soft-deleted (``is_deleted``)."""

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_deleted


class CheckinClassInactiveError(CheckinError):
    """The class exists but is paused (``is_active`` false)."""

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_inactive


class CheckinOccurrenceNotFoundError(CheckinError):
    """The addressed ``(date, time)`` slot is not an occurrence of this class.

    400, not 404, on purpose: occurrences are computed rather than stored, so
    a bad slot is a bad address — and both endpoints have documented the 400
    since they shipped. Changing it is a contract break.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.occurrence_not_found


class CheckinOccurrenceCancelledError(CheckinError):
    """The slot IS an occurrence of the class but that day is cancelled.

    Only the sign-up path raises it — it resolves with
    ``include_cancelled=True`` so a cancelled day reads differently from a
    non-occurrence slot. Check-in drops cancelled occurrences during
    resolution, so there the same slot is ``CheckinOccurrenceNotFoundError``.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.occurrence_cancelled


class CheckinNotOpenYetError(CheckinError):
    """The occurrence starts further out than the check-in open window."""

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.checkin_not_open


class CheckinClassFullError(CheckinError):
    """The occurrence is at its effective ``max_capacity``.

    Counted as the DISTINCT signed-up-or-attended union for the exact slot, so
    a member already counted never blocks on their own presence.
    """

    status_code: int = HTTPStatus.BAD_REQUEST
    code: CheckinErrorCode = CheckinErrorCode.class_full
