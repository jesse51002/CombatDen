SELECT
    discount_id,
    discount_name,
    discount_type,
    percentage_off,
    dollar_off,
    end_date
FROM gym_discounts
WHERE gym_id = :gym_id
  AND discount_active = true
