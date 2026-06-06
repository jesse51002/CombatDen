-- Update a discount IDENTITY. The {set_clause} is built from the changed
-- DiscountUpdateIdentity fields (guarded against GYM_DISCOUNTS), so adding a
-- future editable identity column needs no change here. Value/lifetime edits do
-- NOT happen here — they mint a new gym_discount_values version. Edits affect
-- only future applications; existing applied snapshots are untouched.
UPDATE gym_discounts_unfiltered
SET {set_clause}
WHERE discount_id = :discount_id
  AND is_deleted = false
RETURNING discount_id, gym_id, discount_name, discount_type, is_deleted, created_at
