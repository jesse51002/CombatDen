SELECT DISTINCT date_trunc('week', ma.occurred_at)::date AS week_start
FROM member_attendance ma
WHERE ma.member_id = :member_id
  AND ma.gym_id = :gym_id
ORDER BY week_start DESC
