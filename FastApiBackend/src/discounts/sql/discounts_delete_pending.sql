DELETE FROM gym_discounts_unfiltered
WHERE discount_id = :discount_id AND stripe_coupon_id IS NULL
