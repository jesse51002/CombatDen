-- Which of the candidate plans are allowed to attend a specific class.
-- allowed_plan_ids IS NULL means the class allows every plan; otherwise the
-- JSONB array must contain the plan_id. (is_deleted/is_active are ignored on
-- purpose — a past occurrence of a now-inactive class is still attendable.)
SELECT p.plan_id
FROM gym_classes gc
CROSS JOIN unnest(CAST(:plan_ids AS uuid[])) AS p(plan_id)
WHERE gc.class_id = :class_id
  AND gc.gym_id = :gym_id
  AND (
    gc.allowed_plan_ids IS NULL
    OR gc.allowed_plan_ids @> jsonb_build_array(p.plan_id::text)
  )
