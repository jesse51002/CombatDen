SELECT
    discount_id,
    discount_name,
    discount_type,
    percentage_off,
    dollar_off
FROM gym_discounts
WHERE gym_id = :gym_id
  AND is_deleted = false
