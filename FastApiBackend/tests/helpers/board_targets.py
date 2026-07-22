"""Pick a check-in target off the live schedule board — deterministically.

Both check-in suites need the same scarce thing: a real board occurrence that
can be checked into RIGHT NOW, by member(s) whose membership actually COVERS
it and who are not already on its roster. Getting that wrong does not fail a
test — it makes the fixture hand back ``None`` and every dependent test
``pytest.skip``, which reads as green. So the selection predicate lives here,
once, instead of being re-derived in each suite.

Three rules the naive "first future occurrence" pick got wrong:

1. **Scan BACKWARD as well as forward.** ``CheckinClassResolver`` rejects an
   occurrence more than ``checkin_opens_hours_before_start`` (2h) in the
   future, but explicitly allows every past / in-session one. A forward-only
   scan therefore finds a checkable target ONLY when the gym happens to have a
   class inside the next two hours — so the suite passed in the evening and
   skipped in the morning. The lookback makes yesterday's classes eligible,
   which is what makes the pick hour-independent.

2. **A past occurrence needs a membership that covered it THEN.**
   ``classes_all_memberships.sql`` evaluates coverage at the occurrence's
   instant (``covers_reference``): a membership that started yesterday does
   not cover last Tuesday, and a past freeze window suppresses the days it
   spans. ``status = 'active'`` is a NOW-anchored view status and says nothing
   about either. Without ``covers_occurrence`` below, a retro check-in records
   with a NULL plan/item and 0 points — the tests' ``chosen_plan_id is not
   None`` assertions would fail.

3. **Exclude occurrences the member already attended.** The seed writes a
   month of past attendance, so a past occurrence is quite likely to already
   be on the member's roster — and the fresh-check-in tests assert
   ``already_checked_in is False``.

Coverage is deliberately evaluated against the occurrence's GYM-LOCAL date
(``occurred_at`` in the gym's zone), matching what the backend does, not
against ``original_date`` — the two differ for a rescheduled occurrence near
midnight.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

import asyncpg
import httpx

# How far back / ahead to scan the board. The lookback only has to clear the
# longest realistic gap between classes at a seeded gym; 21 days is far more
# than that while keeping the board response small.
BOARD_LOOKBACK_DAYS = 21
BOARD_WINDOW_DAYS = 45
# Mirrors settings.checkin_opens_hours_before_start.
CHECKIN_OPENS_HOURS = 2

# Every covering member (active, UNLIMITED, plan-eligible) per active class,
# carrying the dates coverage-at-an-instant depends on. UNLIMITED (class_count
# IS NULL) keeps the pick free of pack-exhaustion, which is its own gate.
COVERING_MEMBERS_SQL = """
SELECT
    gc.class_id,
    ms.member_id,
    gc.points_worth,
    ms.start_date,
    ms.freeze_start_date,
    ms.freeze_end_date
FROM member_memberships_status ms
JOIN membership_plans mp
    ON mp.plan_id = ms.plan_id AND mp.gym_id = ms.gym_id
JOIN gym_classes gc
    ON gc.gym_id = ms.gym_id
    AND gc.is_deleted = FALSE
    AND gc.is_active = TRUE
    AND (gc.allowed_plan_ids IS NULL
         OR gc.allowed_plan_ids @> jsonb_build_array(ms.plan_id::text))
WHERE ms.gym_id = $1
  AND ms.status = 'active'
  AND mp.class_count IS NULL
ORDER BY gc.class_id, ms.member_id
"""

# Existing roster rows -> the occurrences a member must NOT be picked for.
ATTENDED_KEYS_SQL = """
SELECT member_id, class_id, original_date, original_time
FROM member_attendance
WHERE gym_id = $1
"""

GYM_TIMEZONE_SQL = """
SELECT timezone FROM gyms WHERE gym_id = $1
"""


async def load_covering(
    conn: asyncpg.Connection, gym_id: str
) -> dict[str, list[dict[str, Any]]]:
    """Covering members grouped by class_id, in a stable member order."""
    rows = await conn.fetch(COVERING_MEMBERS_SQL, UUID(gym_id))
    by_class: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_class.setdefault(str(row["class_id"]), []).append(
            {
                "member_id": str(row["member_id"]),
                "points_worth": int(row["points_worth"]),
                "start_date": row["start_date"],
                "freeze_start_date": row["freeze_start_date"],
                "freeze_end_date": row["freeze_end_date"],
            }
        )
    return by_class


async def load_attended_keys(
    conn: asyncpg.Connection, gym_id: str
) -> set[tuple[str, str, str, str]]:
    """``(member_id, class_id, original_date, original_time)`` already on a
    roster, normalized to the same string shapes the board returns."""
    rows = await conn.fetch(ATTENDED_KEYS_SQL, UUID(gym_id))
    return {
        (
            str(row["member_id"]),
            str(row["class_id"]),
            row["original_date"].isoformat(),
            row["original_time"].isoformat(),
        )
        for row in rows
    }


async def load_gym_timezone(conn: asyncpg.Connection, gym_id: str) -> str:
    return await conn.fetchval(GYM_TIMEZONE_SQL, UUID(gym_id))


def fetch_board(api: httpx.Client, gym_id: str) -> list[dict[str, Any]]:
    """The gym's board occurrences across the scan window (empty on non-200)."""
    today = date.today()
    resp = api.get(
        "/api/v1/classes/instances",
        params={
            "gym_id": gym_id,
            "start_date": (today - timedelta(days=BOARD_LOOKBACK_DAYS)).isoformat(),
            "end_date": (today + timedelta(days=BOARD_WINDOW_DAYS)).isoformat(),
        },
    )
    return resp.json()["items"] if resp.status_code == 200 else []


def is_checkin_open(occurrence: dict[str, Any]) -> bool:
    """Whether check-in is open for this occurrence right now (past and
    in-session occurrences always are)."""
    cutoff = datetime.now(UTC) + timedelta(hours=CHECKIN_OPENS_HOURS)
    return datetime.fromisoformat(occurrence["occurred_at"]) <= cutoff


def occurrence_local_date(occurrence: dict[str, Any], gym_timezone: str) -> date:
    """The occurrence's gym-local calendar date — the reference the coverage
    predicate is evaluated at."""
    started_at = datetime.fromisoformat(occurrence["occurred_at"])
    return started_at.astimezone(ZoneInfo(gym_timezone)).date()


def covers_occurrence(
    cover: dict[str, Any], reference_date: date
) -> bool:
    """Whether this membership covered ``reference_date`` — started on or
    before it and not frozen across it.

    Mirrors ``covers_reference`` in ``classes_all_memberships.sql``. The
    cancel/end legs are omitted on purpose: the covering query already
    restricts to memberships active NOW, so neither can have passed for a
    reference instant that is in the past.
    """
    if cover["start_date"] > reference_date:
        return False
    freeze_start = cover["freeze_start_date"]
    freeze_end = cover["freeze_end_date"]
    return not (
        freeze_start is not None
        and freeze_end is not None
        and freeze_start <= reference_date <= freeze_end
    )


def eligible_members(
    occurrence: dict[str, Any],
    covering: dict[str, list[dict[str, Any]]],
    attended: set[tuple[str, str, str, str]],
    gym_timezone: str,
) -> list[dict[str, Any]]:
    """Covering members who can be freshly checked into this occurrence."""
    covers = covering.get(occurrence["class_id"])
    if not covers:
        return []
    reference_date = occurrence_local_date(occurrence, gym_timezone)
    slot = (
        occurrence["class_id"],
        date.fromisoformat(occurrence["original_date"]).isoformat(),
        time.fromisoformat(occurrence["original_time"]).isoformat(),
    )
    return [
        cover
        for cover in covers
        if covers_occurrence(cover, reference_date)
        and (cover["member_id"], *slot) not in attended
    ]


def pick_occurrence(
    board: list[dict[str, Any]],
    covering: dict[str, list[dict[str, Any]]],
    attended: set[tuple[str, str, str, str]],
    gym_timezone: str,
    *,
    checkin_open: bool,
    min_members: int = 1,
) -> tuple[dict[str, Any], list[dict[str, Any]]] | None:
    """First non-cancelled occurrence on the requested side of the check-in
    window with at least ``min_members`` freshly-checkin-able covering members.

    Returns ``(occurrence, members)`` or ``None``. The board arrives in
    chronological order, so the pick is stable across runs against the same
    seed — every test that writes through it tears its own writes back down.
    """
    for occurrence in board:
        if occurrence["is_cancelled"]:
            continue
        if is_checkin_open(occurrence) != checkin_open:
            continue
        members = eligible_members(occurrence, covering, attended, gym_timezone)
        if len(members) < min_members:
            continue
        return occurrence, members
    return None
