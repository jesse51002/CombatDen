SELECT mpp.price_id,
       mpp.plan_id,
       mpp.gym_id,
       mpp.stripe_price_id,
       mpp.price,
       mpp.is_active,
       mpp.created_at,
       (
         -- The migrate-able set: members actively billing this price (the
         -- same filter the per-plan reprice discovery uses). NOT "active
         -- through the paid period" — a cancelled/deleted row with a future
         -- cancel_date is leaving, not on this price to migrate.
         SELECT count(DISTINCT mm.member_id)
         FROM member_memberships_unfiltered mm
         WHERE mm.price_id = mpp.price_id
           AND mm.plan_id  = mpp.plan_id
           AND mm.stripe_sync_status = 'applied'
           AND mm.cancel_date IS NULL
       ) AS member_count
FROM membership_plan_prices mpp
WHERE mpp.plan_id = :plan_id
  AND mpp.gym_id  = :gym_id
ORDER BY mpp.is_active DESC, mpp.created_at DESC
