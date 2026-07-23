WITH latest_memberships AS (
    SELECT DISTINCT ON (member_id, gym_id, plan_id) *
    FROM member_memberships_status
    ORDER BY member_id, gym_id, plan_id,
             start_date DESC, created_at DESC
)
SELECT
    p.member_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.email,
    p.last_class,
    m.status,
    m.last_paid_date,
    m.next_due_date,
    m.total_price,
    m.end_date,
    m.freeze_end_date,
    m.cancel_date,
    mp.plan_type,
    mp.plan_name,
    mp.duration_unit,
    (now() AT TIME ZONE g.timezone)::date AS gym_today,
    -- Gym-LOCAL date diff, never a bare UTC one: an evening class is
    -- already "tomorrow" in UTC for a gym west of it, so diffing raw
    -- timestamptz dates would go negative for a same-gym-day class. Both
    -- sides are read through the gym's own timezone first, then floored
    -- at 0 (derived numbers never negative).
    CASE
        WHEN p.last_class IS NULL THEN NULL
        ELSE GREATEST(
            0,
            (now() AT TIME ZONE g.timezone)::date
                - (p.last_class AT TIME ZONE g.timezone)::date
        )
    END AS days_since_last_class,
    -- Member-LEVEL dormancy (only short live packs + gone quiet). It is an
    -- aggregate over ALL of the member's memberships, so it cannot be decided
    -- from this row alone -- a member holding a live recurring membership AND
    -- a live trial pack produces two rows here and must never be dormant.
    -- The one shared predicate lives in _member_dormant.sql.
    {is_dormant} AS is_dormant
FROM members p
LEFT JOIN latest_memberships m
    ON p.member_id = m.member_id
    AND p.gym_id = m.gym_id
LEFT JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
ORDER BY p.last_class is null, p.last_class DESC
