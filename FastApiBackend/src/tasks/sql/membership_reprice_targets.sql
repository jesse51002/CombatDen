-- The membership_reprice batch's work discovery (a tasks-side cross-domain
-- read, like the reconciler's member_memberships sweeps): every LIVE
-- membership on the plan that the batch should upgrade to the plan's active
-- price. "Live" = applied (synced) and not cancelled; recurring only
-- (one-time memberships are terminal charges, never repriced). Memberships
-- already referenced by an UNFINISHED task item are skipped (a re-run won't
-- double-task them). Returns the plan's active price id as the pinned target
-- (identical for every row — ≤1 active price per plan). Reads the unfiltered
-- base (service-role).
SELECT
    mm.item_id,
    mm.member_id,
    active.price_id AS target_price_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN membership_plan_prices active
    ON active.plan_id = mm.plan_id
   AND active.gym_id = mm.gym_id
   AND active.is_active = true
WHERE mm.plan_id = :plan_id
  AND mm.gym_id = :gym_id
  AND mp.plan_type = 'recurring'
  AND mm.stripe_sync_status = 'applied'
  AND mm.cancel_date IS NULL
  AND mm.price_id <> active.price_id
  AND NOT EXISTS (
      SELECT 1
      FROM task_items ti
      WHERE (ti.old_item_id = mm.item_id OR ti.new_item_id = mm.item_id)
        AND ti.status IN ('pending', 'running')
  )
ORDER BY mm.created_at, mm.item_id
