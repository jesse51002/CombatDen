-- Pick the concrete membership row (item_id) to charge for a check-in on the
-- chosen plan. Deterministic: earliest start_date, then item_id. Only active
-- memberships are eligible (matches the check-in selection gate).
SELECT item_id
FROM member_memberships_status
WHERE member_id = :member_id
  AND gym_id = :gym_id
  AND plan_id = :plan_id
  AND status = 'active'
ORDER BY start_date ASC, item_id ASC
LIMIT 1
