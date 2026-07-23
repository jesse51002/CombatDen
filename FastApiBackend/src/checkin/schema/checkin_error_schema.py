"""The wire shape of a check-in / sign-up rejection.

Documentation-only: the body itself is written by the single global handler
in ``src/main.py`` (``_handle_checkin_error``), which reads the status and
the ``code`` straight off the raised ``CheckinError``. This model exists so
every endpoint that can reject declares the shape in its OpenAPI
``responses`` and clients can generate against it.
"""

from pydantic import BaseModel

from src.checkin.checkin_exceptions import CheckinErrorCode


class CheckinErrorResponse(BaseModel):
    """A check-in / sign-up rejection body.

    ``code`` is a **sibling** of ``detail``, never nested inside it: the CRM
    reads ``detail`` only when it is a plain String, so an object there would
    degrade every real message to a generic "Server error 400". Switch on
    ``code``; render ``detail``.

    Attributes:
        detail: Human-readable prose. Always a plain string, and free to be
            reworded — it is NOT the discriminator.
        code: The stable machine-readable discriminator. Present on every
            typed domain rejection; ``null`` on the generic bad-input 400 a
            router returns for an unmapped ``ValueError``, so clients fall
            back to ``detail`` when it is absent.
    """

    detail: str
    code: CheckinErrorCode | None = None
