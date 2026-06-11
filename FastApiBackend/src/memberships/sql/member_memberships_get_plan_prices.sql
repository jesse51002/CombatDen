-- Plan + price rows for a start request's distinct price_ids, in one read.
-- A price belongs to exactly one plan, so the price id alone determines the
-- row; plan_id rides along (derived server-side — items don't carry a plan).
SELECT
    mp.plan_id,
    mpp.price_id,
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
WHERE mpp.price_id = ANY(:price_ids)
  AND mp.gym_id    = :gym_id
