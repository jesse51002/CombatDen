SELECT
    gd.discount_id,
    gd.gym_id,
    gd.discount_type
FROM gym_discounts gd
WHERE gd.gym_id = :gym_id
  AND gd.discount_id = ANY(CAST(:discount_ids AS uuid[]))
