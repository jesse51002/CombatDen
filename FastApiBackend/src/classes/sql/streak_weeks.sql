SELECT DISTINCT date_trunc('week', ch.occurred_at)::date AS week_start
FROM member_attendance ma
JOIN class_history ch ON ch.class_history_id = ma.class_history_id
WHERE ma.member_id = :member_id
  AND ma.gym_id = :gym_id
ORDER BY week_start DESC
