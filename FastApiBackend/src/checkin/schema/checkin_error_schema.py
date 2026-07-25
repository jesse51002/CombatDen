"""The wire shape of a check-in / sign-up rejection.

Documentation-only — the body is written by ``_handle_checkin_error`` in
``src/main.py``. This model exists so every rejecting endpoint can declare
the shape in its OpenAPI ``responses`` and clients can generate against it.
"""

from pydantic import BaseModel

from src.checkin.checkin_exceptions import CheckinErrorCode


class CheckinErrorResponse(BaseModel):
    """A check-in / sign-up rejection body: switch on ``code``, render
    ``detail``.

    ``code`` is a **sibling** of ``detail``, never nested inside it — the CRM
    reads ``detail`` only when it is a plain String. It is ``null`` on the
    generic bad-input 400 (an unmapped ``ValueError``), so clients fall back
    to ``detail`` when absent.
    """

    detail: str
    code: CheckinErrorCode | None = None
