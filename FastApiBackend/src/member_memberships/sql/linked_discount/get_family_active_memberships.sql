SELECT mm.member_id, mm.plan_id
FROM member_memberships mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.member_id = ANY(:member_ids)
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
