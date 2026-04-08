UPDATE gym_discounts
SET discount_name      = :discount_name,
    percentage_off     = :percentage_off,
    dollar_off         = :dollar_off,
    duration           = :duration,
    duration_in_months = :duration_in_months,
    stripe_coupon_id   = :stripe_coupon_id
WHERE discount_id = :discount_id
  AND is_deleted = false
RETURNING *
