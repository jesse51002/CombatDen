"""Shared CRM membership-status derivation.

Neither "overdue" nor "dormant" is a stored/DB status — the
``member_memberships_status`` view only derives
``active / frozen / cancelled / ended``. Every CRM read-path that needs
those distinctions derives them the same way, and this module is the
single source of both rules so the members list, its tallies, its
filters, and the member detail endpoints stay in agreement.

- **Overdue**: a non-cancelled membership whose ``next_due_date`` has
  passed the gym's local date. A per-row rule, decided in Python.
- **Dormant**: a member who holds only short (trial / one_time) live
  packs and has gone quiet — an AGGREGATE over all of a member's
  memberships, so the rule itself lives in SQL
  (``sql/crm_views/_member_dormant.sql``, loaded by
  :func:`load_member_dormant_sql`) and Python only decides where the
  resulting flag sits in the badge precedence
  (:func:`is_member_dormant`).
- **Incomplete**: a member who holds no membership of their own AND
  pays for nobody else's — an unfinished signup. Also an aggregate over
  the member's whole membership set (as subject and as payer), so it too
  lives in SQL (``sql/crm_views/_member_incomplete.sql``, loaded by
  :func:`load_member_incomplete_sql`). It has no badge precedence to
  apply: it is a list view + a tally, never a row badge.

This module is a class-less *concern module* — free functions by
design, the sanctioned exception to the no-loose-module-level-functions
rule.
"""

from datetime import date

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.shared.sql_loader import load_sql

# Statuses that OUTRANK dormant on the members-list badge.
#
# Precedence, highest first: overdue > frozen > dormant > trial > active.
#
# - overdue wins because money owed is a different, more urgent action
#   (collect) than a quiet member (re-engage); hiding a payment problem
#   behind "dormant" would be a regression.
# - frozen wins because a freeze is an explicit, staff-initiated pause
#   with an end date — the member's absence is expected and already
#   labelled, so calling them dormant would be noise, not news.
# - cancelled / ended are here for completeness only: the SQL rule
#   requires a LIVE membership, so an all-terminal member is never
#   flagged dormant in the first place. A member holding BOTH a terminal
#   and a live short pack can still be dormant — the live pack is what
#   the badge is about.
# - dormant BEATS trial (and plain active) on purpose, and that collision
#   is the whole point of the status: a dormant member holds a trial /
#   one_time pack by definition, so if trial won, dormant could never
#   render and the misleading "Active"/"Trial" badge this fixes would
#   survive. "Trial" says a prospect is in progress; for someone who
#   bought a pack and vanished a month ago that is the least honest thing
#   the list can say.
DORMANT_YIELDS_TO: frozenset[CrmMemberStatus] = frozenset(
    {
        CrmMemberStatus.overdue,
        CrmMemberStatus.frozen,
        CrmMemberStatus.cancelled,
        CrmMemberStatus.ended,
    },
)

DORMANT_SQL_PATH = SQL_DIR / "crm_views" / "_member_dormant.sql"
INCOMPLETE_SQL_PATH = SQL_DIR / "crm_views" / "_member_incomplete.sql"


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


def is_member_dormant(
    status: CrmMemberStatus,
    is_dormant: bool | None,
) -> bool:
    """Return whether a row should display the dormant badge.

    The member-level dormancy test itself is SQL
    (``_member_dormant.sql``); this only applies the badge precedence
    documented on :data:`DORMANT_YIELDS_TO`.

    Args:
        status: The status derived for the row so far (raw DB status,
            already promoted to ``overdue`` if it is overdue).
        is_dormant: The SQL-computed member-level dormancy flag, or
            ``None`` when the query did not select it.

    Returns:
        ``True`` when the member is dormant and no higher-precedence
        status has already claimed the badge.
    """
    return bool(is_dormant) and status not in DORMANT_YIELDS_TO


def load_member_dormant_sql(
    member_id_expr: str,
    gym_id_expr: str,
) -> str:
    """Load the correlated dormancy predicate for an outer query.

    The one text backs the badge (``all_view.sql``), the tally
    (``total_counts.sql``), and the members-list status filter, so the
    three can never drift. It binds ``dormancy_days``, which the caller
    must supply.

    Args:
        member_id_expr: SQL expression for the outer query's member id
            (e.g. ``"p.member_id"``).
        gym_id_expr: SQL expression for the outer query's gym id (e.g.
            ``"p.gym_id"``).

    Returns:
        A self-contained boolean SQL expression.
    """
    return load_sql(
        DORMANT_SQL_PATH,
        {"member_id": member_id_expr, "gym_id": gym_id_expr},
    )


def load_member_incomplete_sql(
    member_id_expr: str,
    gym_id_expr: str,
) -> str:
    """Load the correlated incomplete-signup predicate for an outer query.

    The one text backs the Incomplete tab's list (``incomplete_view.sql``)
    and its tally (``total_counts.sql``), so the two can never drift.
    Unlike the dormancy predicate it binds no parameters.

    Args:
        member_id_expr: SQL expression for the outer query's member id
            (e.g. ``"p.member_id"``).
        gym_id_expr: SQL expression for the outer query's gym id (e.g.
            ``"p.gym_id"``).

    Returns:
        A self-contained boolean SQL expression.
    """
    return load_sql(
        INCOMPLETE_SQL_PATH,
        {"member_id": member_id_expr, "gym_id": gym_id_expr},
    )
