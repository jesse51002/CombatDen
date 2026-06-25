-- A real gym's active reward cards for the showcase, in points-store order.
SELECT
    title,
    image_url,
    price_label,
    point_cost AS points_cost
FROM gym_rewards
WHERE gym_id = CAST(:gym_id AS UUID)
  AND is_active = TRUE
ORDER BY point_cost
