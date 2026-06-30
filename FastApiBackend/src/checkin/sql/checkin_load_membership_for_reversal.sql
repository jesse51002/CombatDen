-- The auto-end inputs for the pack a removed attendance was charged to: its
-- current end_date, plan_type, and effective capacity inputs (plan.class_count
-- and the membership's quantity). Mirrors classes_undo_find_attendees.sql for a
-- single pack so a single-member removal reverses an auto-end exactly as the
-- whole-occurrence undo does. Read at service_role off the unfiltered base
-- tables (the filtered views hide pre-sync rows).
SELECT
    mm.end_date,
    mp.plan_type,
    mp.class_count,
    mm.quantity
FROM member_memberships_unfiltered mm
JOIN membership_plans_unfiltered mp
    ON mp.plan_id = mm.plan_id
WHERE mm.item_id = CAST(:item_id AS UUID)
