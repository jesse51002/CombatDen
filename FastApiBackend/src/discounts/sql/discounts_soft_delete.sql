UPDATE gym_discounts_unfiltered
SET is_deleted = true
WHERE discount_id = :discount_id
  AND gym_id = :gym_id
  AND is_deleted = false
RETURNING *
