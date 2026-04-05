SELECT
    gc.class_id,
    p.plan_id
FROM gym_classes gc
CROSS JOIN unnest(CAST(:plan_ids AS uuid[])) AS p(plan_id)
WHERE gc.gym_id = :gym_id
  AND (
    gc.allowed_plan_ids IS NULL
    OR gc.allowed_plan_ids @> jsonb_build_array(p.plan_id::text)
  )
