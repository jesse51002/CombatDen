-- Up-front validation read for a batch start's requested discount_ids: each
-- must be a live (non-archived) discount in this gym with an ACTIVE value
-- version. Returns discount_type so the service can reject `custom` ids —
-- customs are creation-only inline values, never referenced by id.
SELECT
    d.discount_id,
    d.discount_type
FROM gym_discounts d
JOIN gym_discount_values v
    ON v.discount_id = d.discount_id
   AND v.is_active = true
WHERE d.discount_id = ANY(:discount_ids)
  AND d.gym_id = :gym_id
  AND d.is_deleted = false
