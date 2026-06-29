-- The memberships that have attendance against one materialized occurrence,
-- with the fields the auto-end reversal needs: the membership's current
-- end_date, its plan_type, and its effective pack capacity inputs
-- (plan.class_count and the membership's quantity). The effective capacity is
-- class_count * quantity -- the SAME capacity the check-in's auto-end uses
-- (see classes_all_memberships.sql), so the reversal mirrors the auto-end
-- exactly. Read at service_role off the unfiltered base tables (the filtered
-- views hide pre-sync rows).
SELECT DISTINCT
    ma.item_id,
    ma.member_id,
    mm.end_date,
    mp.plan_type,
    mp.class_count,
    mm.quantity
FROM member_attendance ma
JOIN member_memberships_unfiltered mm
    ON mm.item_id = ma.item_id
JOIN membership_plans_unfiltered mp
    ON mp.plan_id = ma.plan_id
WHERE ma.class_history_id = CAST(:class_history_id AS UUID)
