SELECT
    mpp.stripe_price_id,
    mp.duration_unit,
    mpp.price
FROM membership_plan_prices mpp
JOIN membership_plans mp
    ON mpp.plan_id = mp.plan_id AND mpp.gym_id = mp.gym_id
WHERE mpp.stripe_price_id = ANY(:stripe_price_ids)
