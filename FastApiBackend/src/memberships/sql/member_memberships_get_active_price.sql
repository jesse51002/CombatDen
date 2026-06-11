SELECT
    mpp.price_id,
    mpp.stripe_price_id,
    mpp.price
FROM membership_plan_prices mpp
WHERE mpp.plan_id = :plan_id
  AND mpp.gym_id  = :gym_id
  AND mpp.is_active = true
