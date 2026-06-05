-- Fetch a non-deleted discount joined to its active value version. The identity
-- (name, type) lives on gym_discounts; the percent/dollar + lifetime live on the
-- active gym_discount_values row.
SELECT
    d.discount_id,
    d.gym_id,
    d.discount_name,
    d.discount_type,
    d.is_deleted,
    d.created_at,
    v.value_id,
    v.percentage_off,
    v.dollar_off,
    v.discount_mode,
    v.duration_amount,
    v.duration_unit,
    v.end_date
FROM gym_discounts d
JOIN gym_discount_values v
    ON v.discount_id = d.discount_id
   AND v.is_active = true
WHERE d.discount_id = :discount_id
  AND d.is_deleted = false
