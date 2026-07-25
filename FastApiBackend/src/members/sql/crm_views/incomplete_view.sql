-- Incomplete signups. The rule is the shared predicate injected below from
-- _member_incomplete.sql -- which owns the reasoning for each clause -- so
-- this list and the total_counts tally can never disagree.
--
-- NEVER name a template variable in braces inside these comments: load_sql
-- runs str.format_map over the WHOLE file, comments included, so the brace
-- form splices the injected predicate into the comment and the file stops
-- parsing.
--
-- The latest_memberships / membership_plans LEFT JOINs are NOT dead weight:
-- the shared CrmBaseViewService builds the where-clause and may reference the
-- `m` and `mp` aliases, so both must resolve here as in every sibling view.
-- Every matched row is NULL on both sides by construction.
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
    p.phone,
    (now() AT TIME ZONE g.timezone)::date AS gym_today,
    -- Gym-LOCAL date diff, never a bare UTC one (same as all_view.sql's
    -- days_since_last_class): an evening signup is already "tomorrow" in UTC
    -- for a gym west of it, so a raw diff reports a day that hasn't happened.
    GREATEST(
        0,
        (now() AT TIME ZONE g.timezone)::date
            - (p.created_at AT TIME ZONE g.timezone)::date
    ) AS days_waiting
FROM members p
LEFT JOIN latest_memberships m
    ON p.member_id = m.member_id
    AND p.gym_id = m.gym_id
LEFT JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
    AND {is_incomplete}
-- Newest first: an unfinished signup is most convertible while the person is
-- still in the building.
ORDER BY p.created_at DESC, p.member_id
LIMIT :limit OFFSET :offset
