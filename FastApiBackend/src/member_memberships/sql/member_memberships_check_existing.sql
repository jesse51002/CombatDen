SELECT 1
FROM member_memberships_status
WHERE member_id = :member_id
  AND gym_id    = :gym_id
  AND plan_id   = :plan_id
  AND status IN ('active', 'frozen')
