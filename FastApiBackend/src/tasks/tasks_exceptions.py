"""Custom exceptions for the tasks domain."""


class MembershipInTaskError(Exception):
    """A membership mutation hit a row referenced by an unfinished task.

    Raised by the in-task guard (``TasksService.assert_memberships_not_in_task``)
    when an operation targets a membership row that a pending/running task item
    references — either as the row being acted on or as the successor row the
    operation is producing. Routers map it to 409.
    """
