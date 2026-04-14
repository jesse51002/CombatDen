SELECT DISTINCT mm.crm_user_id
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
WHERE mm.plan_id = :plan_id
  AND (mm.cancel_date IS NULL OR mm.cancel_date > (now() AT TIME ZONE g.timezone)::date)
  AND (mm.end_date IS NULL OR mm.end_date > (now() AT TIME ZONE g.timezone)::date)
