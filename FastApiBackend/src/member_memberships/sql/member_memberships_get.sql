SELECT
    mm.plan_id,
    mm.gym_id,
    mp.plan_type,
    mp.duration_unit,
    mp.duration_amount,
    mm.next_due_date,
    mm.cancel_date,
    mm.end_date,
    mm.price_id,
    mpp.stripe_price_id,
    mm.stripe_item_id,
    mm.discount_ids,
    mpp.price,
    g.timezone
FROM member_memberships mm
JOIN membership_plans mp
  ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN membership_plan_prices mpp
  ON mm.price_id = mpp.price_id AND mm.gym_id = mpp.gym_id
JOIN gyms g ON g.gym_id = mm.gym_id
WHERE mm.item_id   = :item_id
  AND mm.member_id = :member_id
