-- Read a live (non-archived) preset's ACTIVE value version so the apply path can
-- freeze the membership to that immutable value_id and resolve its absolute
-- end_date from the version's lifetime spec. A later edit mints a NEW version,
-- so an applied row stays pinned to the value_id captured here.
SELECT
    d.discount_id,
    d.discount_type,
    v.value_id,
    v.discount_mode,
    v.duration_amount,
    v.duration_unit,
    v.end_date
FROM gym_discounts d
JOIN gym_discount_values v
    ON v.discount_id = d.discount_id
   AND v.is_active = true
WHERE d.discount_id = :discount_id
  AND d.gym_id = :gym_id
  AND d.is_deleted = false
