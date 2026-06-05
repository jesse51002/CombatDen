-- List preset discounts for a gym, each joined to its active value version.
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
WHERE d.gym_id = :gym_id
  AND d.is_deleted = false
  AND d.discount_type = 'preset'
ORDER BY d.created_at DESC
