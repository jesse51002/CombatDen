-- The members who attended one materialized class occurrence. Joins the
-- attendance log to members for the display name and carries the billing
-- attribution (plan_id / item_id), both NULL for a no-membership staff
-- check-in. gym_id scopes the read to the requesting employee's gym.
SELECT
    ma.member_id,
    m.first_name || ' ' || m.last_name AS full_name,
    ma.log_id,
    ma.plan_id,
    ma.item_id
FROM member_attendance ma
JOIN members m
    ON  m.member_id = ma.member_id
    AND m.gym_id = ma.gym_id
WHERE ma.class_history_id = CAST(:class_history_id AS UUID)
  AND ma.gym_id = CAST(:gym_id AS UUID)
ORDER BY m.first_name, m.last_name
