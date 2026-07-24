-- Incomplete signups: members who exist as a row but never finished buying
-- anything, and who are not paying for anybody either. The rule itself is the
-- shared predicate injected below from _member_incomplete.sql, so this list and
-- the total_counts tally can never disagree.
--
-- NOTE: never name a template variable in braces inside these comments --
-- load_sql runs str.format_map over the WHOLE file, comments included, so the
-- brace form would splice the whole injected predicate into the comment block
-- (its later lines then land as bare SQL and the file stops parsing).
--
-- The latest_memberships / membership_plans LEFT JOINs are NOT dead weight:
-- the where-clause is built by the shared CrmBaseViewService and may reference
-- the `m` (membership) and `mp` (plan) aliases, so both must resolve here as
-- they do in every sibling view. By construction every matched row has NULL on
-- both sides, so a membership-shaped filter correctly matches nothing while the
-- no_membership filter still matches everything.
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
    -- Gym-LOCAL date diff, never a bare UTC one (same reasoning as
    -- all_view.sql's days_since_last_class): a member created in the evening
    -- is already "tomorrow" in UTC for a gym west of it, so a raw timestamptz
    -- diff would report a day that has not happened yet. Both sides are read
    -- through the gym's own timezone first, then floored at 0.
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
-- still in the building, so the freshest one is the one staff should act on.
ORDER BY p.created_at DESC, p.member_id
LIMIT :limit OFFSET :offset
