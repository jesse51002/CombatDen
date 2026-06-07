"""Shared CRM membership-status derivation.

"Overdue" is not a stored/DB status — the ``member_memberships_status``
view only derives ``active / frozen / cancelled / ended``. Every CRM
read-path that needs the overdue distinction derives it the same way:
a non-cancelled membership whose ``next_due_date`` has passed the gym's
local date. This module is the single source of that rule so the members
list and the member detail endpoints stay in agreement.
"""

from datetime import date

from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)


def is_membership_overdue(
    status: str,
    next_due: date | None,
    today: date,
) -> bool:
    """Return whether a membership row is overdue.

    Args:
        status: The raw DB membership status (``CrmMemberStatus`` is a
            ``StrEnum`` so a raw DB string compares equal to it).
        next_due: The membership's next due date, if any.
        today: The gym's local current date.

    Returns:
        ``True`` when the membership is not cancelled and its next due
        date has already passed.
    """
    return status != CrmMemberStatus.cancelled and next_due is not None and next_due < today
