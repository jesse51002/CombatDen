-- Read the PAYER's PENDING non-recurring memberships for the one-time sync —
-- every row whose paid_by_member_id is this payer. Covers BOTH 'one_time' and
-- 'trial' plans: a trial is billed identically as a $0 line on the same
-- consolidated invoice, so it gets the same two-id writeback and 'applied'
-- confirmation as a paid one-time. Reads the UNFILTERED base table
-- (service-role) so the just-inserted PENDING rows (stripe_sync_status
-- 'not_added') are visible — the sync bills them on a single consolidated
-- invoice and stamps each.
--
-- One-time is TERMINAL: the real path reads only 'not_added' rows (the just-
-- inserted, never-charged ones). An already-'applied' row has been charged and
-- must NEVER be re-read (re-reading would re-charge it), so unlike the recurring
-- read there is no 'applied'/'migrating' inclusion. The PREVIEW path also reads
-- 'preview_add' (the staged row a start preview cuts then rolls back) via
-- :statuses. A one-time plan may have no duration, so duration_unit can be NULL.
SELECT
    mm.item_id,
    mm.member_id,
    mm.plan_id,
    mm.price_id,
    mpp.stripe_price_id,
    mpp.price,
    mm.stripe_item_id,
    mp.duration_unit
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN membership_plan_prices mpp
    ON mm.price_id = mpp.price_id AND mm.gym_id = mpp.gym_id
WHERE mm.paid_by_member_id = :payer_member_id
  AND mp.plan_type IN ('one_time', 'trial')
  AND mm.stripe_sync_status::text = ANY(:statuses)
