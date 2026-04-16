WITH latest_memberships AS (
    SELECT DISTINCT ON (crm_user_id, gym_id, plan_id) *
    FROM member_memberships_status
    ORDER BY crm_user_id, gym_id, plan_id,
             start_date DESC, created_at DESC
)
SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    MIN(m.freeze_start_date) AS freeze_start_date,
    MAX(m.freeze_end_date) AS freeze_end_date,
    MIN(m.freeze_end_date) AS earliest_freeze_end,
    ARRAY_AGG(m.total_price) AS prices,
    ARRAY_AGG(mp.duration_unit) AS duration_units,
    (now() AT TIME ZONE g.timezone)::date AS gym_today
FROM user_gym_profiles p
JOIN latest_memberships m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
GROUP BY p.crm_user_id, p.first_name, p.last_name, p.photo_url, g.timezone
ORDER BY
    ((now() AT TIME ZONE g.timezone)::date - MIN(m.freeze_end_date)) ASC
LIMIT :limit OFFSET :offset
