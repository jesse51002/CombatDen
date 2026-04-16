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
    MAX(m.start_date) AS start_date,
    MAX(m.end_date) AS end_date,
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
    AND mp.plan_type = 'trial'
    AND NOT EXISTS (
        SELECT 1
        FROM member_memberships_status m2
        JOIN membership_plans mp2
            ON m2.plan_id = mp2.plan_id
            AND m2.gym_id = mp2.gym_id
        WHERE m2.crm_user_id = p.crm_user_id
        AND m2.gym_id = p.gym_id
        AND (
            (
                m2.status = 'active' AND mp2.plan_type ='recurring'
            )
            OR (
                mp2.plan_type ='one_time' and m2.start_date > m.start_date
            )
        )
    )
GROUP BY p.crm_user_id, p.first_name, p.last_name, p.photo_url, g.timezone
ORDER BY (MAX(m.end_date) - (now() AT TIME ZONE g.timezone)::date) DESC
LIMIT :limit OFFSET :offset
