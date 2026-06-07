-- Deactivate the current active value version of a discount. Run immediately
-- before inserting a new active version, so the partial unique index
-- (<=1 active per discount) is satisfied. The deactivated row stays as history.
UPDATE gym_discount_values_unfiltered
SET is_active = false
WHERE discount_id = :discount_id
  AND is_active = true
