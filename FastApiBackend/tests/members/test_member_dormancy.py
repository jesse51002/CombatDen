"""Tests for the CRM members-list ``dormant`` status.

Dormancy is a MEMBER-level rule — "every live membership is a short
(trial / one_time) pack AND the member has gone quiet" is an aggregate
over all of a member's memberships — so the rule itself lives in SQL
(``src/members/sql/crm_views/_member_dormant.sql``) and only its badge
precedence is decided in Python. The tests split the same way:

- The behavioural matrix runs the REAL fragment text against Postgres
  over synthetic rows. A ``WITH members AS (...)`` CTE **shadows** the
  real table for the whole query (a WITH name hides a same-named table),
  so the fragment is exercised verbatim against rows the test controls,
  with **no writes at all** — every statement here is a SELECT over
  literals. That matters: a Python re-implementation of the rule would
  be a second source of truth and could pass while the shipped SQL was
  wrong.
- The precedence, filter, and tally-assembly tests are hermetic.
"""

from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.growth import SQL_DIR as GROWTH_SQL_DIR
from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
    MembersListFilters,
    MembersListTotalCounts,
)
from src.members.service.crm_member_services.members_crm_all_service import (
    CrmAllViewService,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.members.service.crm_member_services.members_crm_total_counts_service import (
    DORMANT_COUNT_SQL,
    INCOMPLETE_COUNT_SQL,
    OVERDUE_COUNT_SQL,
)
from src.members.service.members_status_mapping import (
    DORMANT_YIELDS_TO,
    is_member_dormant,
    load_member_dormant_sql,
)
from src.shared.sql_loader import load_sql
from tests.seed_constants import SEEDED_GYM_ID

DORMANCY_DAYS = 30
TZ = "America/Chicago"

# One live membership, described as (plan_type, status, start_days_ago).
Membership = tuple[str, str, int]

TRIAL_LIVE_TODAY: Membership = ("trial", "active", 0)
TRIAL_LIVE_OLD: Membership = ("trial", "active", 60)
ONE_TIME_LIVE_OLD: Membership = ("one_time", "active", 60)
RECURRING_LIVE_OLD: Membership = ("recurring", "active", 60)
TRIAL_FROZEN_OLD: Membership = ("trial", "frozen", 60)
TRIAL_CANCELLED: Membership = ("trial", "cancelled", 60)
TRIAL_ENDED: Membership = ("trial", "ended", 60)


def _synthetic_query(
    memberships: list[Membership],
    body: str,
) -> tuple[str, dict]:
    """Wrap ``body`` in CTEs that shadow the real tables it reads.

    The CTE names (``members`` / ``gyms`` / ``member_memberships_status``
    / ``membership_plans``) hide the real tables for this statement, so
    the shipped SQL runs verbatim over rows the test supplies. Nothing is
    written — the whole statement is a SELECT over literals. Every bind
    is cast at its use site so Postgres can resolve the type of a
    parameter sitting in a bare VALUES row.

    Args:
        memberships: The one member's memberships.
        body: SQL appended after the CTE list.

    Returns:
        Tuple of (SQL, params).
    """
    gym_id = str(uuid4())
    params: dict = {"member_id": str(uuid4()), "gym_id": gym_id, "tz": TZ}
    plan_rows: list[str] = []
    membership_rows: list[str] = []

    for i, (plan_type, status, start_days_ago) in enumerate(memberships):
        params[f"plan_{i}"] = str(uuid4())
        params[f"type_{i}"] = plan_type
        params[f"status_{i}"] = status
        params[f"start_{i}"] = date.today() - timedelta(days=start_days_ago)
        plan_rows.append(
            f"(CAST(:plan_{i} AS UUID), CAST(:gym_id AS UUID), "
            f"CAST(:type_{i} AS TEXT))"
        )
        membership_rows.append(
            f"(CAST(:member_id AS UUID), CAST(:gym_id AS UUID), "
            f"CAST(:plan_{i} AS UUID), CAST(:status_{i} AS TEXT), "
            f"CAST(:start_{i} AS DATE))"
        )

    sql = f"""
        WITH members AS (
            SELECT
                CAST(:member_id AS UUID) AS member_id,
                CAST(:gym_id AS UUID) AS gym_id,
                CAST(:last_class AS TIMESTAMPTZ) AS last_class
        ),
        gyms AS (
            SELECT
                CAST(:gym_id AS UUID) AS gym_id,
                CAST(:tz AS TEXT) AS timezone
        ),
        membership_plans AS (
            SELECT * FROM (VALUES {", ".join(plan_rows)})
                AS v(plan_id, gym_id, plan_type)
        ),
        member_memberships_status AS (
            SELECT * FROM (VALUES {", ".join(membership_rows)})
                AS v(member_id, gym_id, plan_id, status, start_date)
        )
        {body}
    """
    return sql, params


async def _is_dormant(
    db_pool,
    memberships: list[Membership],
    last_class_days_ago: int | None = None,
) -> bool:
    """Run the real dormancy fragment over one synthetic member.

    Args:
        db_pool: The session-scoped database pool fixture.
        memberships: The member's memberships.
        last_class_days_ago: Days since their last check-in, or None for
            a member who has never attended.

    Returns:
        The fragment's verdict for that member.
    """
    predicate = load_member_dormant_sql(
        "CAST(:member_id AS UUID)",
        "CAST(:gym_id AS UUID)",
    )
    sql, params = _synthetic_query(
        memberships,
        f"SELECT {predicate} AS is_dormant",
    )
    params["dormancy_days"] = DORMANCY_DAYS
    params["last_class"] = (
        None
        if last_class_days_ago is None
        else datetime.now(UTC) - timedelta(days=last_class_days_ago)
    )

    async with db_pool.session() as session:
        result = await session.execute(text(sql), params)
        return result.scalar_one()


# -- The rule (real SQL, synthetic rows, read-only) --


async def test_fresh_trial_pack_with_no_checkins_is_not_dormant(db_pool) -> None:
    """THE never-attended guard: a pack bought TODAY is not dormancy.

    Branding a day-one lead as gone-quiet is a false positive on the
    newest and most valuable member the gym has, and is exactly what
    anchoring on GREATEST(check-in, live pack start) prevents.
    """
    assert await _is_dormant(db_pool, [TRIAL_LIVE_TODAY]) is False


async def test_old_trial_pack_with_no_checkins_is_dormant(db_pool) -> None:
    """The same member 60 days later, still never attended, is dormant."""
    assert await _is_dormant(db_pool, [TRIAL_LIVE_OLD]) is True


async def test_old_one_time_pack_with_no_checkins_is_dormant(db_pool) -> None:
    """one_time is a short plan too — not just trials."""
    assert await _is_dormant(db_pool, [ONE_TIME_LIVE_OLD]) is True


async def test_live_recurring_alongside_old_trial_is_not_dormant(db_pool) -> None:
    """THE aggregate case a per-row implementation gets wrong.

    The member holds a quiet old trial pack AND a live recurring
    membership. The trial row alone looks dormant; the member is not.
    """
    assert (
        await _is_dormant(db_pool, [TRIAL_LIVE_OLD, RECURRING_LIVE_OLD])
        is False
    )


async def test_recent_checkin_is_not_dormant(db_pool) -> None:
    """A check-in yesterday keeps an old pack's holder active."""
    assert (
        await _is_dormant(db_pool, [TRIAL_LIVE_OLD], last_class_days_ago=1)
        is False
    )


async def test_stale_checkin_and_stale_pack_is_dormant(db_pool) -> None:
    """Both activity signals older than the window means dormant."""
    assert (
        await _is_dormant(db_pool, [TRIAL_LIVE_OLD], last_class_days_ago=45)
        is True
    )


async def test_re_buying_a_pack_restarts_the_clock(db_pool) -> None:
    """GREATEST, not a null fallback: a fresh pack outranks an old visit.

    A returning member whose last check-in was 90 days ago but who bought
    a new pack 5 days ago is not dormant — the pack start is the later of
    the two activity dates.
    """
    assert (
        await _is_dormant(
            db_pool,
            [("trial", "active", 5)],
            last_class_days_ago=90,
        )
        is False
    )


async def test_all_terminal_memberships_are_not_dormant(db_pool) -> None:
    """Scope boundary: the list keeps calling these cancelled / ended.

    The analytics side counts an all-terminal member as churn; this
    surface deliberately does not, because cancelled / ended is already
    accurate here and is a distinction staff rely on.
    """
    assert (
        await _is_dormant(db_pool, [TRIAL_CANCELLED, TRIAL_ENDED]) is False
    )


async def test_terminal_plus_live_short_pack_is_dormant(db_pool) -> None:
    """A dead membership does not shield a quiet live pack."""
    assert (
        await _is_dormant(db_pool, [TRIAL_CANCELLED, TRIAL_LIVE_OLD]) is True
    )


async def test_frozen_short_pack_is_flagged_by_the_rule(db_pool) -> None:
    """A freeze is not terminal, so the SQL rule still flags the member.

    The badge is another matter — frozen outranks dormant in Python (see
    the precedence tests below). Keeping the SQL rule identical to the
    analytics one and resolving the collision at display time is
    deliberate.
    """
    assert await _is_dormant(db_pool, [TRIAL_FROZEN_OLD]) is True


async def test_dormancy_boundary_is_strict(db_pool) -> None:
    """Exactly at the window is still active; one day past is dormant."""
    assert (
        await _is_dormant(db_pool, [("trial", "active", DORMANCY_DAYS)])
        is False
    )
    assert (
        await _is_dormant(db_pool, [("trial", "active", DORMANCY_DAYS + 1)])
        is True
    )


# -- The tally (real total_counts.sql, synthetic rows, read-only) --


async def test_total_counts_tallies_dormant_members(db_pool) -> None:
    """``total_counts.sql``'s dormant column counts dormant members.

    Two dormant members (one quiet trial pack each) and one active
    recurring member share the gym; only the two are tallied. This also
    proves the dormant scalar subquery is legal beside the aggregates.
    """
    gym_id = str(uuid4())
    dormant_a, dormant_b, healthy = uuid4(), uuid4(), uuid4()
    start_old = date.today() - timedelta(days=60)
    plan_trial, plan_recurring = str(uuid4()), str(uuid4())

    sql = f"""
        WITH members AS (
            SELECT * FROM (VALUES
                (CAST(:m_a AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_a'),
                (CAST(:m_b AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_b'),
                (CAST(:m_c AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_c')
            ) AS v(member_id, gym_id, last_class, stripe_customer_id)
        ),
        gyms AS (
            SELECT
                CAST(:gym_id AS UUID) AS gym_id,
                CAST(:tz AS TEXT) AS timezone
        ),
        membership_plans AS (
            SELECT * FROM (VALUES
                (CAST(:plan_trial AS UUID), CAST(:gym_id AS UUID), 'trial'),
                (CAST(:plan_recurring AS UUID), CAST(:gym_id AS UUID),
                 'recurring')
            ) AS v(plan_id, gym_id, plan_type)
        ),
        member_memberships_unfiltered AS (
            -- Shadowed EMPTY on purpose. The shared incomplete predicate
            -- (_member_incomplete.sql) also excludes a member holding a
            -- billed-but-unconfirmed non-recurring row, so it reads this
            -- table; these synthetic worlds have no such row, and the CTE
            -- must exist because every real relation the injected SQL touches
            -- is shadowed here (otherwise the query escapes into the live DB).
            SELECT
                CAST(NULL AS UUID) AS member_id,
                CAST(NULL AS UUID) AS paid_by_member_id,
                CAST(NULL AS UUID) AS gym_id,
                CAST(NULL AS UUID) AS plan_id,
                CAST(NULL AS TEXT) AS stripe_sync_status
            WHERE false
        ),
        member_memberships_status AS (
            SELECT * FROM (VALUES
                (CAST(:m_a AS UUID), CAST(:m_a AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_trial AS UUID), 'active',
                 CAST(:start_old AS DATE), CAST(NULL AS DATE),
                 CAST(now() AS TIMESTAMPTZ)),
                (CAST(:m_b AS UUID), CAST(:m_b AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_trial AS UUID), 'active',
                 CAST(:start_old AS DATE), CAST(NULL AS DATE),
                 CAST(now() AS TIMESTAMPTZ)),
                (CAST(:m_c AS UUID), CAST(:m_c AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_recurring AS UUID), 'active',
                 CAST(:start_old AS DATE), CAST(NULL AS DATE),
                 CAST(now() AS TIMESTAMPTZ))
            ) AS v(member_id, paid_by_member_id, gym_id, plan_id, status,
                   start_date, next_due_date, created_at)
        )
        {load_sql(SQL_DIR / "crm_views" / "total_counts.sql",
                  {"is_dormant": DORMANT_COUNT_SQL,
                   "is_incomplete": INCOMPLETE_COUNT_SQL,
                   "is_overdue": OVERDUE_COUNT_SQL})}
    """
    params = {
        "gym_id": gym_id,
        "tz": TZ,
        "m_a": str(dormant_a),
        "m_b": str(dormant_b),
        "m_c": str(healthy),
        "plan_trial": plan_trial,
        "plan_recurring": plan_recurring,
        "start_old": start_old,
        "dormancy_days": DORMANCY_DAYS,
    }

    async with db_pool.session() as session:
        result = await session.execute(text(sql), params)
        row = result.mappings().one()

    counts = MembersListTotalCounts(
        active=row["active"],
        trial=row["trial"],
        frozen=row["frozen"],
        overdue=row["overdue"],
        dormant=row["dormant"],
        incomplete=row["incomplete"],
    )
    assert counts.dormant == 2
    # The tallies overlap by design: the two dormant members hold trials
    # and are still counted there too.
    assert counts.trial == 2
    assert counts.active == 1
    # Every synthetic member holds a membership, so nobody is an
    # incomplete signup — the two tallies stay independent.
    assert counts.incomplete == 0


async def test_total_counts_overdue_counts_only_active(db_pool) -> None:
    """``total_counts.sql``'s overdue tally counts ONLY active rows.

    A frozen, cancelled or ended membership keeps its stale past
    ``next_due_date`` forever, and none of the three is money the gym can
    still collect — a frozen one is a deliberate pause billing $0, and the
    other two are finished. Counting them would drift the subtitle above
    what the Overdue tab lists and would overstate recoverable revenue.
    Four past-due members share the gym, one per status; only the active
    one is overdue.
    """
    gym_id = str(uuid4())
    active_due, cancelled_due = uuid4(), uuid4()
    frozen_due, ended_due = uuid4(), uuid4()
    start_old = date.today() - timedelta(days=60)
    past_due = date.today() - timedelta(days=10)
    plan_recurring = str(uuid4())

    sql = f"""
        WITH members AS (
            SELECT * FROM (VALUES
                (CAST(:m_a AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_a'),
                (CAST(:m_b AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_b'),
                (CAST(:m_c AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_c'),
                (CAST(:m_d AS UUID), CAST(:gym_id AS UUID),
                 CAST(NULL AS TIMESTAMPTZ), 'cus_synthetic_d')
            ) AS v(member_id, gym_id, last_class, stripe_customer_id)
        ),
        gyms AS (
            SELECT
                CAST(:gym_id AS UUID) AS gym_id,
                CAST(:tz AS TEXT) AS timezone
        ),
        membership_plans AS (
            SELECT * FROM (VALUES
                (CAST(:plan_recurring AS UUID), CAST(:gym_id AS UUID),
                 'recurring')
            ) AS v(plan_id, gym_id, plan_type)
        ),
        member_memberships_unfiltered AS (
            -- Shadowed EMPTY on purpose. The shared incomplete predicate
            -- (_member_incomplete.sql) also excludes a member holding a
            -- billed-but-unconfirmed non-recurring row, so it reads this
            -- table; these synthetic worlds have no such row, and the CTE
            -- must exist because every real relation the injected SQL touches
            -- is shadowed here (otherwise the query escapes into the live DB).
            SELECT
                CAST(NULL AS UUID) AS member_id,
                CAST(NULL AS UUID) AS paid_by_member_id,
                CAST(NULL AS UUID) AS gym_id,
                CAST(NULL AS UUID) AS plan_id,
                CAST(NULL AS TEXT) AS stripe_sync_status
            WHERE false
        ),
        member_memberships_status AS (
            SELECT * FROM (VALUES
                (CAST(:m_a AS UUID), CAST(:m_a AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_recurring AS UUID), 'active',
                 CAST(:start_old AS DATE), CAST(:past_due AS DATE),
                 CAST(now() AS TIMESTAMPTZ)),
                (CAST(:m_b AS UUID), CAST(:m_b AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_recurring AS UUID), 'cancelled',
                 CAST(:start_old AS DATE), CAST(:past_due AS DATE),
                 CAST(now() AS TIMESTAMPTZ)),
                (CAST(:m_c AS UUID), CAST(:m_c AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_recurring AS UUID), 'frozen',
                 CAST(:start_old AS DATE), CAST(:past_due AS DATE),
                 CAST(now() AS TIMESTAMPTZ)),
                (CAST(:m_d AS UUID), CAST(:m_d AS UUID),
                 CAST(:gym_id AS UUID),
                 CAST(:plan_recurring AS UUID), 'ended',
                 CAST(:start_old AS DATE), CAST(:past_due AS DATE),
                 CAST(now() AS TIMESTAMPTZ))
            ) AS v(member_id, paid_by_member_id, gym_id, plan_id, status,
                   start_date, next_due_date, created_at)
        )
        {load_sql(SQL_DIR / "crm_views" / "total_counts.sql",
                  {"is_dormant": DORMANT_COUNT_SQL,
                   "is_incomplete": INCOMPLETE_COUNT_SQL,
                   "is_overdue": OVERDUE_COUNT_SQL})}
    """
    params = {
        "gym_id": gym_id,
        "tz": TZ,
        "m_a": str(active_due),
        "m_b": str(cancelled_due),
        "m_c": str(frozen_due),
        "m_d": str(ended_due),
        "plan_recurring": plan_recurring,
        "start_old": start_old,
        "past_due": past_due,
        "dormancy_days": DORMANCY_DAYS,
    }

    async with db_pool.session() as session:
        result = await session.execute(text(sql), params)
        row = result.mappings().one()

    counts = MembersListTotalCounts(
        active=row["active"],
        trial=row["trial"],
        frozen=row["frozen"],
        overdue=row["overdue"],
        dormant=row["dormant"],
        incomplete=row["incomplete"],
    )
    # Only the active past-due membership is overdue; the frozen,
    # cancelled and ended ones are excluded despite their stale dates.
    assert counts.overdue == 1
    assert counts.active == 1
    # A cancelled membership still disqualifies its member from the
    # incomplete list — they finished a signup once, they are lapsed, not
    # unfinished.
    assert counts.incomplete == 0


# -- Badge precedence (hermetic) --

_ALL_SERVICE = CrmAllViewService(None, DORMANCY_DAYS)  # type: ignore[arg-type]


def _row(**overrides) -> dict:
    row = {
        "member_id": uuid4(),
        "first_name": "Ada",
        "last_name": "Lovelace",
        "photo_url": None,
        "email": "ada@example.com",
        "status": CrmMemberStatus.active.value,
        "plan_type": "trial",
        "next_due_date": None,
        "gym_today": date(2026, 7, 20),
        "total_price": 0,
        "duration_unit": "month",
        "days_since_last_class": None,
        "is_dormant": True,
    }
    row.update(overrides)
    return row


def test_dormant_beats_trial_on_the_badge() -> None:
    """The bug this fixes: a quiet trial-pack holder read as in-progress.

    Every dormant member holds a trial / one_time pack by definition, so
    dormant and trial always collide. Trial winning would make dormant
    unreachable and keep showing the misleading label.
    """
    mapped = _ALL_SERVICE._map_row(_row())
    assert mapped.membership_status == CrmMemberStatus.dormant


def test_dormant_beats_plain_active_on_the_badge() -> None:
    """A quiet one_time pack holder is dormant, not Active."""
    mapped = _ALL_SERVICE._map_row(_row(plan_type="one_time"))
    assert mapped.membership_status == CrmMemberStatus.dormant


def test_overdue_beats_dormant() -> None:
    """Money owed is a different, more urgent action than a quiet member."""
    mapped = _ALL_SERVICE._map_row(_row(next_due_date=date(2026, 7, 1)))
    assert mapped.membership_status == CrmMemberStatus.overdue


def test_frozen_beats_dormant() -> None:
    """A freeze is an expected, already-labelled, dated absence.

    Chasing a member the gym itself agreed to pause is a worse error
    than a slightly noisy tally, so frozen keeps the badge.
    """
    mapped = _ALL_SERVICE._map_row(
        _row(status=CrmMemberStatus.frozen.value, plan_type="one_time"),
    )
    assert mapped.membership_status == CrmMemberStatus.frozen


def test_terminal_statuses_are_untouched() -> None:
    """Cancelled / ended keep their own labels, flag or no flag."""
    for terminal in (CrmMemberStatus.cancelled, CrmMemberStatus.ended):
        mapped = _ALL_SERVICE._map_row(
            _row(status=terminal.value, plan_type="one_time"),
        )
        assert mapped.membership_status == terminal


def test_not_dormant_falls_through_to_trial() -> None:
    """Without the flag, the pre-existing trial badge still wins."""
    mapped = _ALL_SERVICE._map_row(_row(is_dormant=False))
    assert mapped.membership_status == CrmMemberStatus.trial


def test_missing_flag_is_treated_as_not_dormant() -> None:
    """A query that never selected the column must not crash or flag."""
    row = _row()
    del row["is_dormant"]
    assert _ALL_SERVICE._map_row(row).membership_status == CrmMemberStatus.trial


def test_precedence_set_is_exactly_the_documented_one() -> None:
    """Locks the ranking: overdue / frozen / terminal outrank dormant."""
    expected = {
        CrmMemberStatus.overdue,
        CrmMemberStatus.frozen,
        CrmMemberStatus.cancelled,
        CrmMemberStatus.ended,
    }
    assert set(DORMANT_YIELDS_TO) == expected
    assert is_member_dormant(CrmMemberStatus.active, True) is True
    assert is_member_dormant(CrmMemberStatus.trial, True) is True
    assert is_member_dormant(CrmMemberStatus.frozen, True) is False
    assert is_member_dormant(CrmMemberStatus.active, None) is False


# -- The filter (hermetic + live smoke) --

_BASE_SERVICE = CrmBaseViewService(None, DORMANCY_DAYS)  # type: ignore[arg-type]


def test_dormant_filter_uses_the_shared_predicate() -> None:
    """The filter reuses the one dormancy text, not a second copy."""
    where, params = _BASE_SERVICE.build_where_clause(
        UUID(SEEDED_GYM_ID),
        MembersListFilters(membership_status=[CrmMemberStatus.dormant]),
    )
    shared = load_member_dormant_sql("p.member_id", "p.gym_id")
    assert shared in where
    assert params["dormancy_days"] == DORMANCY_DAYS
    # Matches only where the badge renders: a live, not-past-due row.
    # "Not past due" is the NEGATION of the one shared overdue predicate,
    # never a second hand-written copy.
    assert "m.status = :st_active_dormant" in where
    assert "NOT (" in where
    assert "m.next_due_date < " in where
    assert params["st_active_dormant"] == "active"


def test_dormant_filter_ands_with_other_dimensions() -> None:
    """Status stays one OR-group AND-ed with the other dimensions."""
    where, _ = _BASE_SERVICE.build_where_clause(
        UUID(SEEDED_GYM_ID),
        MembersListFilters(
            membership_status=[CrmMemberStatus.dormant],
            name="ada",
        ),
    )
    assert where.startswith("WHERE p.gym_id = :gym_id AND (")
    assert "ILIKE :name_search" in where


def test_no_dormancy_bind_when_dormant_is_not_selected() -> None:
    """The window is only bound when the predicate is actually used."""
    _, params = _BASE_SERVICE.build_where_clause(
        UUID(SEEDED_GYM_ID),
        MembersListFilters(membership_status=[CrmMemberStatus.frozen]),
    )
    assert "dormancy_days" not in params


async def test_dormant_filtered_all_view_agrees_with_the_badge(db_pool) -> None:
    """Live read-only check against the seeded gym.

    Proves the assembled query is valid SQL with every bind supplied, and
    that filter and badge agree: every row the dormant filter returns
    maps to the dormant badge.
    """
    service = CrmAllViewService(db_pool, DORMANCY_DAYS)
    async with db_pool.session() as session:
        rows = await service.fetch(
            session,
            UUID(SEEDED_GYM_ID),
            MembersListFilters(membership_status=[CrmMemberStatus.dormant]),
            0,
            100,
        )
    assert all(
        row.membership_status == CrmMemberStatus.dormant for row in rows
    )


async def test_unfiltered_all_view_still_runs(db_pool) -> None:
    """The added dormancy column does not break the default list read."""
    service = CrmAllViewService(db_pool, DORMANCY_DAYS)
    async with db_pool.session() as session:
        rows = await service.fetch(
            session,
            UUID(SEEDED_GYM_ID),
            MembersListFilters(),
            0,
            5,
        )
    assert all(row.membership_status in set(CrmMemberStatus) for row in rows)


# -- Drift guard against the analytics rule --


def test_members_and_growth_dormancy_share_the_never_attended_guard() -> None:
    """The two surfaces must not drift on the load-bearing parts.

    ``src/growth/sql/_dormant_members.sql`` is the canonical reference.
    Both must anchor activity on GREATEST(check-in, newest live pack
    start) and both must require zero live recurring memberships —
    neither may be simplified into a bare "no check-in means dormant".
    """
    paths = (
        SQL_DIR / "crm_views" / "_member_dormant.sql",
        GROWTH_SQL_DIR / "_dormant_members.sql",
    )
    for path in paths:
        # Comments quote the wrong form on purpose, so compare the
        # executable body only.
        sql = "\n".join(
            line
            for line in path.read_text().splitlines()
            if not line.lstrip().startswith("--")
        )
        assert "GREATEST(" in sql
        assert "'recurring'" in sql
        assert "last_class IS NULL" not in sql
        assert "AT TIME ZONE" in sql
        assert "CURRENT_DATE" not in sql
