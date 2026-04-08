SELECT
    discount_id,
    stripe_coupon_id,
    dollar_off
FROM gym_discounts
WHERE discount_id = ANY(:discount_ids)
  AND is_deleted = false
  AND stripe_coupon_id IS NOT NULL
