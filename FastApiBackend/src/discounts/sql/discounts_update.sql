-- Update a discount IDENTITY (only discount_name is editable). Value/lifetime
-- edits do NOT happen here — they mint a new gym_discount_values version. Edits
-- affect only future applications; existing applied snapshots are untouched.
UPDATE gym_discounts_unfiltered
SET discount_name = :discount_name
WHERE discount_id = :discount_id
  AND is_deleted = false
RETURNING discount_id, gym_id, discount_name, discount_type, is_deleted, created_at
