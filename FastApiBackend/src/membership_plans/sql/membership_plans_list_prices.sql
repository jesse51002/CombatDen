SELECT mpp.price_id,
       mpp.plan_id,
       mpp.gym_id,
       mpp.stripe_price_id,
       mpp.price,
       mpp.is_active,
       mpp.created_at,
       (
         SELECT count(DISTINCT mm.member_id)
         FROM member_memberships mm
         JOIN gyms g ON g.gym_id = mm.gym_id
         WHERE mm.price_id = mpp.price_id
           AND mm.plan_id  = mpp.plan_id
           AND (mm.cancel_date IS NULL OR mm.cancel_date > (now() AT TIME ZONE g.timezone)::date)
           AND (mm.end_date   IS NULL OR mm.end_date   > (now() AT TIME ZONE g.timezone)::date)
       ) AS member_count
FROM membership_plan_prices mpp
WHERE mpp.plan_id = :plan_id
  AND mpp.gym_id  = :gym_id
ORDER BY mpp.is_active DESC, mpp.created_at DESC
