"""Unit tests for ``CrmAllViewService``'s row mapping.

Focused on the ``days_since_last_class`` regression: the "Last class: -1
days" bug came from computing a UTC instant diff in Python
(``datetime.now(UTC) - last_class_dt``), which goes negative for an evening
gym-local class (already "tomorrow" in UTC for a gym west of it) or during
the 2h early-check-in window. The fix moved the computation into
``all_view.sql`` as a gym-local DATE diff clamped at 0 (matching the views'
existing ``gym_today`` idiom); the service now reads that column directly
rather than re-deriving it. These tests pin the read-through, not the SQL
(no DB — the SQL's own correctness is covered live by the schedule-board /
members-list integration suite).
"""

from uuid import uuid4

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.members.schema.members_crm_members_list_schema import CrmMemberStatus
from src.members.service.crm_member_services.members_crm_all_service import (
    CrmAllViewService,
)

# Pool unused here; the dormancy window only matters to the SQL path.
_SERVICE = CrmAllViewService(None, 30)  # type: ignore[arg-type]


def test_days_since_last_class_reads_the_sql_column_directly() -> None:
    """The value comes straight off the row's ``days_since_last_class``
    column (gym-local, clamped at 0 by ``all_view.sql``) — no Python
    re-derivation from a raw ``last_class`` instant."""
    row = {"last_class": "2026-06-20T09:00:00+00:00", "days_since_last_class": 3}
    assert _SERVICE._days_since_last_class(row) == 3


def test_days_since_last_class_zero_is_not_treated_as_falsy() -> None:
    """A same-gym-day class (clamped to 0, never negative) surfaces as 0."""
    row = {"last_class": "2026-07-02T20:00:00+00:00", "days_since_last_class": 0}
    assert _SERVICE._days_since_last_class(row) == 0


def test_days_since_last_class_none_when_no_last_class() -> None:
    row = {"last_class": None, "days_since_last_class": None}
    assert _SERVICE._days_since_last_class(row) is None


def test_map_row_no_membership_surfaces_days_since_last_class() -> None:
    """End-to-end through ``_map_row``'s no-membership branch."""
    row = {
        "member_id": uuid4(),
        "first_name": "Ada",
        "last_name": "Lovelace",
        "photo_url": None,
        "email": "ada@example.com",
        "status": None,
        "days_since_last_class": 5,
    }
    mapped = _SERVICE._map_row(row)
    assert mapped.membership_status == CrmMemberStatus.no_membership
    assert mapped.days_since_last_class == 5
