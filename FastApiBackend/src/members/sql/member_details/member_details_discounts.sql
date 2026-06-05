-- Gym discounts (identity + active value version) as a lookup for the member
-- billing detail. The percent/dollar live on the active gym_discount_values row.
SELECT
    d.discount_id,
    d.discount_name,
    d.discount_type,
    v.percentage_off,
    v.dollar_off
FROM gym_discounts d
JOIN gym_discount_values v
    ON v.discount_id = d.discount_id
   AND v.is_active = true
WHERE d.gym_id = :gym_id
  AND d.is_deleted = false
