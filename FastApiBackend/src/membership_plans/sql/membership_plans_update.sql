UPDATE membership_plans
SET {set_clause}
WHERE plan_id = :plan_id
  AND gym_id  = :gym_id
  AND is_deleted = false
RETURNING *
