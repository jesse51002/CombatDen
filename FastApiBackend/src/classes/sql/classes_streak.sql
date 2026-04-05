SELECT DISTINCT date_trunc('week', time)::date AS week_start
FROM gym_classes_log
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
ORDER BY week_start DESC
