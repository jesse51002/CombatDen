"""Custom exceptions for the employees domain.

The service layer raises these; the router maps each to its HTTP status
(404 / 403 / 409). All subclass ``ValueError`` so a generic
``except ValueError`` in the router still catches an unmapped domain error
as a 400 (bad input) rather than a 500.
"""


class EmployeeNotFoundError(ValueError):
    """The target employee row does not exist (or is archived) at the gym.

    Router → 404.
    """


class DuplicateEmployeeError(ValueError):
    """An employee with this email already exists at this gym.

    Raised when the plain INSERT violates the ``unique_employee_email_gym``
    partial unique index on ``(gym_id, lower(email))``. Router → 409.
    """


class OwnerRowProtectedError(ValueError):
    """A protected owner-row rule was violated.

    The owner row can only be edited by the owner themselves, the owner's
    ``employee_type`` can never change, and the owner can never be archived.
    Router → 403.
    """
