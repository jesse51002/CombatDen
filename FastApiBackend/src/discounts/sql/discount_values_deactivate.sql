-- Deactivate the current active value version of a discount. Run immediately
-- before inserting a new active version, so the partial unique index
-- (<=1 active per discount) is satisfied. The deactivated row stays as history.
-- The gym_id predicate is defense-in-depth (the caller already gym-scopes via
-- _get_discount); it keeps the deactivate self-contained and IDOR-safe.
UPDATE gym_discount_values_unfiltered
SET is_active = false
WHERE discount_id = :discount_id
  AND gym_id = :gym_id
  AND is_active = true
