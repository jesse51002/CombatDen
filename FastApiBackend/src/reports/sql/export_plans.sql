-- Raw membership plans for the gym (UNFILTERED base table). waiver_ids is a
-- JSONB array rendered as its text form.
SELECT
    p.plan_id,
    p.gym_id,
    p.plan_name,
    p.plan_type,
    p.class_count,
    p.duration_amount,
    p.duration_unit,
    p.is_public,
    p.is_deleted,
    p.stripe_product_id,
    CAST(p.waiver_ids AS TEXT) AS waiver_ids,
    p.image_url,
    p.created_at
FROM membership_plans_unfiltered p
WHERE p.gym_id = CAST(:gym_id AS UUID)
ORDER BY p.created_at ASC, p.plan_id ASC
