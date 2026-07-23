"""Canonical membership-OVERDUE derivation, shared across domains.

"Overdue" is not a stored status -- the ``member_memberships_status``
view derives only ``active / frozen / cancelled / ended``. Every surface
that needs the distinction derives it the same way, and this module is
THE single source of that rule. The Python predicate
(:func:`is_membership_overdue`) and the SQL text
(:func:`load_membership_overdue_sql`, backed by
``sql/membership_overdue.sql``) are the two faces of ONE definition, so
the members-list badge, its tally, its status filter, the member-detail
endpoints, the growth revenue tiles, and the check-in gate can never
disagree about who owes. Change one face and you must change the other.

WHY ``shared`` AND NOT ``members``: ``src.members`` already imports
``src.checkin`` (the member-detail cycle-counts bridge pulls
``CycleCountsService`` / ``MembershipUsage``). Housing the rule in
``members`` and importing it from the check-in gate would close that
into a package cycle, so the only acyclic home for a predicate both
domains need is ``shared``.

This module is a class-less *concern module* -- free functions by
design, the sanctioned exception to the
no-loose-module-level-functions rule.
"""

from datetime import date

import src.shared.db_schema_path  # noqa: F401  # isort: skip

from schema.member_membership import MembershipDbStatus

from src.shared import SQL_DIR
from src.shared.sql_loader import load_sql

OVERDUE_SQL_PATH = SQL_DIR / "membership_overdue.sql"


def is_membership_overdue(
    status: str,
    next_due: date | None,
    today: date,
) -> bool:
    """Return whether a membership row is overdue.

    The Python twin of ``sql/membership_overdue.sql``; see that file for
    the full reasoning behind each clause.

    Args:
        status: The raw DB membership status (``MembershipDbStatus`` is a
            ``StrEnum``, so a raw DB string compares equal to it).
        next_due: The membership's next due date, if any.
        today: The gym's LOCAL current date -- never a bare UTC date.

    Returns:
        ``True`` when the membership is active and its next due date has
        already passed. A frozen / cancelled / ended membership is never
        overdue: none of them is money the gym can still collect.
    """
    return (
        status == MembershipDbStatus.active
        and next_due is not None
        and next_due < today
    )


def load_membership_overdue_sql(alias: str, today: str) -> str:
    """Load the overdue predicate for an outer query.

    Args:
        alias: SQL alias of the membership row to test (e.g. ``"m"``,
            ``"mms"``).
        today: SQL expression for the gym's LOCAL current date (e.g.
            ``"(now() AT TIME ZONE g.timezone)::date"`` or a
            precomputed bounds-CTE column such as ``"b.today"``).

    Returns:
        A self-contained boolean SQL expression.
    """
    return load_sql(OVERDUE_SQL_PATH, {"alias": alias, "today": today})
