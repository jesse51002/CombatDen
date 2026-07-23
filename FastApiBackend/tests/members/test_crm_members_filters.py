"""Unit tests for the CRM members-list filter builder.

``CrmBaseViewService.build_where_clause`` is pure (no DB), so these run
without a pool. They lock in the filter semantics the CRM relies on:

- each dimension (status / plan / date / name) narrows the result and is
  **AND-combined** with the others — the regression these guard is the old
  behavior where status and date were OR-joined into one group;
- within the status dimension the selected statuses **OR** together;
- the new ``plan_ids`` dimension filters to members holding any given plan.
"""

from uuid import uuid4

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
    DateRangeFilter,
    MembersListFilters,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)

# build_where_clause never touches the pool, so a None pool is fine here.
_SERVICE = CrmBaseViewService(None, 30)  # type: ignore[arg-type]
_GYM = uuid4()


def _build(filters: MembersListFilters) -> tuple[str, dict]:
    return _SERVICE.build_where_clause(_GYM, filters)


def test_no_filters_is_gym_only() -> None:
    where, params = _build(MembersListFilters())
    assert where == "WHERE p.gym_id = :gym_id"
    assert params == {"gym_id": str(_GYM)}


def test_frozen_status_predicate() -> None:
    where, params = _build(
        MembersListFilters(membership_status=[CrmMemberStatus.frozen]),
    )
    assert where == "WHERE p.gym_id = :gym_id AND ((m.status = :st_frozen))"
    assert params["st_frozen"] == "frozen"


def test_active_status_matches_the_active_badge() -> None:
    # "Active" the badge = a live, paid, non-trial membership that is not
    # past due — so the predicate excludes trial plans and overdue rows.
    where, params = _build(
        MembersListFilters(membership_status=[CrmMemberStatus.active]),
    )
    assert "m.status = :st_active" in where
    assert "mp.plan_type != :pt_trial" in where  # excludes trials
    # Excludes overdue as the NEGATION of the ONE shared predicate, so
    # "is overdue" and "is not overdue" can never drift apart.
    assert "NOT (" in where
    assert "m.next_due_date < " in where
    assert params["st_active"] == "active"
    assert params["pt_trial"] == "trial"


def test_overdue_status_is_active_only() -> None:
    where, _ = _build(
        MembersListFilters(membership_status=[CrmMemberStatus.overdue]),
    )
    # The shared predicate: ONLY an active membership can be overdue. A
    # frozen one bills $0 and a cancelled / ended one is finished, so
    # none of them is money the gym can still collect.
    assert "m.status = 'active'" in where
    assert "m.next_due_date IS NOT NULL" in where
    assert "m.next_due_date < " in where
    # The old hand-written "not cancelled" form is gone for good.
    assert "m.status != :st_cancelled" not in where


def test_multiple_statuses_or_within_dimension() -> None:
    where, _ = _build(
        MembersListFilters(
            membership_status=[CrmMemberStatus.active, CrmMemberStatus.overdue],
        ),
    )
    # active and overdue are two distinct predicates that OR together
    # inside one AND-ed status group.
    assert " OR " in where
    assert "mp.plan_type != :pt_trial" in where  # the active predicate
    assert "m.status = 'active'" in where  # the overdue predicate


def test_plan_ids_filter_is_anded_in_and_scoped_to_live() -> None:
    plan_a, plan_b = uuid4(), uuid4()
    where, params = _build(MembersListFilters(plan_ids=[plan_a, plan_b]))
    # A plan filter matches only LIVE (active/frozen) memberships on the
    # plan — cancelled/ended holders never match.
    assert where == (
        "WHERE p.gym_id = :gym_id AND ("
        "mp.plan_id IN (:plan_0, :plan_1) "
        "AND m.status IN (:plan_live_0, :plan_live_1))"
    )
    assert params["plan_0"] == str(plan_a)
    assert params["plan_1"] == str(plan_b)
    assert {params["plan_live_0"], params["plan_live_1"]} == {
        "active",
        "frozen",
    }


def test_rank_ids_filter_is_ored_via_any() -> None:
    rank_a, rank_b = uuid4(), uuid4()
    where, params = _build(MembersListFilters(rank_ids=[rank_a, rank_b]))
    # A rank filter matches any member currently at one of the given
    # ranks, via a single ANY(CAST(... AS UUID[])) array bind.
    assert where == (
        "WHERE p.gym_id = :gym_id AND "
        "p.current_rank_id = ANY(CAST(:rank_ids AS UUID[]))"
    )
    assert params["rank_ids"] == [str(rank_a), str(rank_b)]


def test_rank_ids_empty_list_is_no_filter() -> None:
    # Mirrors plan_ids: an empty list means "no filter" — the clause is
    # omitted entirely and the param is never bound.
    where, params = _build(MembersListFilters(rank_ids=[]))
    assert where == "WHERE p.gym_id = :gym_id"
    assert "rank_ids" not in params


def test_date_range_both_bounds_anded() -> None:
    where, params = _build(
        MembersListFilters(
            date_range=DateRangeFilter(
                start_date="2026-01-01",
                end_date="2026-02-01",
            ),
        ),
    )
    assert "m.start_date >= :date_start" in where
    assert "m.start_date <= :date_end" in where
    # Range bounds AND together, never OR.
    assert " OR " not in where
    assert params["date_start"] == "2026-01-01"
    assert params["date_end"] == "2026-02-01"


def test_name_search_is_anded_ilike() -> None:
    where, params = _build(MembersListFilters(name="ada"))
    assert "ILIKE :name_search" in where
    assert " AND " in where
    assert params["name_search"] == "%ada%"


def test_dimensions_are_and_combined_not_or() -> None:
    """The key regression: status, plan, date and name AND together.

    The status dimension keeps its internal OR, but the dimensions
    themselves are joined with AND — a member must match every active
    dimension, not any one of them.
    """
    plan = uuid4()
    where, _ = _build(
        MembersListFilters(
            membership_status=[CrmMemberStatus.frozen],
            plan_ids=[plan],
            date_range=DateRangeFilter(start_date="2026-01-01"),
            name="ada",
        ),
    )
    assert where == (
        "WHERE p.gym_id = :gym_id"
        " AND ((m.status = :st_frozen))"
        " AND (mp.plan_id IN (:plan_0)"
        " AND m.status IN (:plan_live_0, :plan_live_1))"
        " AND m.start_date >= :date_start"
        " AND (p.first_name || ' ' || p.last_name ILIKE :name_search)"
    )
