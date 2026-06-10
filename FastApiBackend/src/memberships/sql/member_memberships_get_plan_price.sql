SELECT
    mp.plan_type,
    mp.duration_amount,
    mp.duration_unit,
    mp.is_deleted   AS plan_is_deleted,
    mpp.stripe_price_id,
    mpp.price,
    mpp.is_active   AS price_is_active
FROM membership_plans mp
JOIN membership_plan_prices mpp
  ON mpp.plan_id = mp.plan_id AND mpp.gym_id = mp.gym_id
WHERE mp.plan_id   = :plan_id
  AND mp.gym_id    = :gym_id
  AND mpp.price_id = :price_id
