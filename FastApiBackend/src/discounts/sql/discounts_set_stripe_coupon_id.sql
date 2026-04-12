UPDATE gym_discounts_unfiltered
SET stripe_coupon_id = :stripe_coupon_id
WHERE discount_id = :discount_id
RETURNING *
