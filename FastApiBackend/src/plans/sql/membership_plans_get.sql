SELECT mp.*,
       mpp.price_id        AS price_price_id,
       mpp.stripe_price_id AS price_stripe_price_id,
       mpp.price           AS price_price,
       mpp.is_active       AS price_is_active,
       mpp.created_at      AS price_created_at,
       (
         SELECT coalesce(
                  jsonb_agg(
                    jsonb_build_object(
                      'percentage_off', v.percentage_off,
                      'dollar_off', v.dollar_off
                    ) ORDER BY e.ord
                  ),
                  '[]'::jsonb
                )
         FROM jsonb_array_elements_text(mp.linked_discount_ids)
              WITH ORDINALITY AS e(discount_id, ord)
         JOIN gym_discount_values v
              ON v.discount_id = e.discount_id::uuid
             AND v.gym_id      = mp.gym_id
             AND v.is_active    = true
       ) AS linked_discount_values
FROM membership_plans mp
LEFT JOIN membership_plan_prices mpp
       ON mpp.plan_id  = mp.plan_id
      AND mpp.gym_id   = mp.gym_id
      AND mpp.is_active = true
WHERE mp.plan_id    = :plan_id
  AND mp.gym_id     = :gym_id
  AND mp.is_deleted = false
