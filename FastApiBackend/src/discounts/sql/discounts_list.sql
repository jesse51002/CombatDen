SELECT *
FROM gym_discounts
WHERE gym_id = :gym_id
  AND is_deleted = false
  AND discount_type = 'preset'
ORDER BY created_at DESC
