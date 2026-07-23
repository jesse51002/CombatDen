-- Raw class attendance rows for the gym.
SELECT
    a.log_id,
    a.member_id,
    a.gym_id,
    a.class_id,
    a.original_date,
    a.original_time,
    a.occurred_at,
    a.plan_id,
    a.item_id
FROM member_attendance a
WHERE a.gym_id = CAST(:gym_id AS UUID)
ORDER BY a.occurred_at ASC, a.log_id ASC
