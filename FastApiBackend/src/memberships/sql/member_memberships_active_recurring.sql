SELECT mm.item_id, mm.gym_id, mm.plan_id
FROM member_memberships mm
JOIN membership_plans mp
  ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN gyms g ON g.gym_id = mm.gym_id
WHERE mm.member_id = :member_id
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND (mm.end_date IS NULL OR mm.end_date > (now() AT TIME ZONE g.timezone)::date)
