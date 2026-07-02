-- The auto-end inputs for the pack a removed attendance was charged to: its
-- current end_date, plan_type, effective capacity inputs (plan.class_count
-- and the membership's quantity — class_count * quantity, the SAME capacity
-- the check-in's auto-end uses, so the reversal mirrors it exactly), and the
-- duration inputs (start_date + plan duration) the un-end needs to RESTORE
-- the purchase-stamped expiry instead of blindly NULLing it. Read at
-- service_role off the unfiltered base tables (the filtered views hide
-- pre-sync rows).
SELECT
    mm.end_date,
    mm.start_date,
    mp.plan_type,
    mp.class_count,
    mp.duration_amount,
    mp.duration_unit,
    mm.quantity
FROM member_memberships_unfiltered mm
JOIN membership_plans_unfiltered mp
    ON mp.plan_id = mm.plan_id
WHERE mm.item_id = CAST(:item_id AS UUID)
