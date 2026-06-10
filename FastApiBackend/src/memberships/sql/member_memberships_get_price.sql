SELECT
    mpp.stripe_price_id,
    mpp.price,
    mpp.is_active
FROM membership_plan_prices mpp
WHERE mpp.price_id = :price_id
  AND mpp.plan_id  = :plan_id
  AND mpp.gym_id   = :gym_id
