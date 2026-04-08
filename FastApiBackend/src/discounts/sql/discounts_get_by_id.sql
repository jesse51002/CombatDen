SELECT *
FROM gym_discounts
WHERE discount_id = :discount_id
  AND is_deleted = false
