# Handoff: Members list filter composition (backend)

## Bug

`FastApiBackend/src/members/service/crm_member_services/members_crm_base_service.py:72-81` lumps the `name` filter into the same list as status/date filters, then joins that whole list with `OR`:

```python
if filters.name:
    user_filters.append(
        "(p.first_name || ' ' || p.last_name ILIKE :name_search)",
    )
    params["name_search"] = f"%{filters.name}%"

where = "WHERE p.gym_id = :gym_id"
if user_filters:
    where += " AND (" + " OR ".join(user_filters) + ")"
```

Effect: a search for `name="Jesse"` + `membership_status=["active"]` returns *"name matches Jesse OR anyone active"* instead of *"Jesse AND active"*.

## Fix

Keep the existing OR behavior for status/date filters (intentional — status filters already OR among themselves, and callers may be relying on that shape). Pull the `name` filter out and AND it on separately.

Sketch:

```python
def build_where_clause(
    self, gym_id, filters,
) -> tuple[str, dict]:
    params = {"gym_id": str(gym_id)}
    user_filters: list[str] = []

    if filters.membership_status:
        self._apply_status_filter(
            filters.membership_status, user_filters, params,
        )

    if filters.date_range:
        if filters.date_range.start_date:
            user_filters.append("m.start_date >= :date_start")
            params["date_start"] = filters.date_range.start_date.isoformat()
        if filters.date_range.end_date:
            user_filters.append("m.start_date <= :date_end")
            params["date_end"] = filters.date_range.end_date.isoformat()

    where = "WHERE p.gym_id = :gym_id"
    if user_filters:
        where += " AND (" + " OR ".join(user_filters) + ")"

    # Name is ANDed separately, outside the OR group.
    if filters.name:
        where += (
            " AND (p.first_name || ' ' || p.last_name "
            "ILIKE :name_search)"
        )
        params["name_search"] = f"%{filters.name}%"

    return where, params
```

Resulting SQL with both filters set:

```
WHERE p.gym_id = :gym_id
  AND (<status/date OR-group>)
  AND (p.first_name || ' ' || p.last_name ILIKE :name_search)
```

## Affected call sites

All view services call `build_where_clause` via `CrmBaseViewService` — they inherit the fix, no edits needed:

- `members_crm_all_service.py`
- `members_crm_trial_service.py`
- `members_crm_frozen_service.py`
- `members_crm_overdue_service.py`
- `members_crm_cancelled_service.py`

## Verify

1. Seed a gym with: active "Jesse", active "Alex", frozen "Jesse Two".
2. `POST /api/v1/members/crm_members_list` with `filters.name="Jesse"` + `filters.membership_status=["active"]`.
3. Expect: only active Jesse. Not Alex (wrong name) and not frozen Jesse Two (wrong status).
4. Sanity-check that a status-only request still returns every active member (the OR-group for status is unchanged).
