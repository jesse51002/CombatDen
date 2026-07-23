-- Raw membership plan price versions for the gym (UNFILTERED base table).
SELECT
    pp.price_id,
    pp.plan_id,
    pp.gym_id,
    pp.stripe_price_id,
    pp.price,
    pp.is_active,
    pp.created_at
FROM membership_plan_prices_unfiltered pp
WHERE pp.gym_id = CAST(:gym_id AS UUID)
ORDER BY pp.created_at ASC, pp.price_id ASC
