UPDATE gym_discounts
SET is_deleted = true
WHERE discount_id = :discount_id
  AND is_deleted = false
RETURNING *
