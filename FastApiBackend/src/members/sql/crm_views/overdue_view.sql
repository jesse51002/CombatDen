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
    MIN(m.next_due_date) AS next_due_date,
    ARRAY_AGG(mp.plan_name) AS plan_names,
    ARRAY_AGG(m.total_price) AS prices,
    ARRAY_AGG(mp.duration_unit) AS duration_units,
    (now() AT TIME ZONE g.timezone)::date AS gym_today
FROM members p
JOIN latest_memberships m
    ON p.member_id = m.member_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON g.gym_id = p.gym_id
{where_clause}
    AND m.status != 'cancelled'
    AND m.next_due_date < (now() AT TIME ZONE g.timezone)::date
GROUP BY p.member_id, p.first_name, p.last_name, p.photo_url,
    p.email, p.phone, g.timezone
ORDER BY
    ((now() AT TIME ZONE g.timezone)::date - MIN(m.next_due_date)) ASC
LIMIT :limit OFFSET :offset
