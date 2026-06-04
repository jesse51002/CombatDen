SELECT
    mm.member_id,
    mm.plan_id,
    mm.price_id,
    mpp.stripe_price_id,
    mm.stripe_item_id,
    mp.duration_unit,
    mm.discount_ids,
    mpp.price
FROM member_memberships mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN membership_plan_prices mpp
    ON mm.price_id = mpp.price_id AND mm.gym_id = mpp.gym_id
WHERE mm.member_id = ANY(:member_ids)
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
