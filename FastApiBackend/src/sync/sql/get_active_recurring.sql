-- Read the PAYER's desired-active recurring memberships for the sync. Scope is
-- the payer: every row whose paid_by_member_id is this payer (their own
-- memberships and any family member's memberships they pay for). Reads the
-- UNFILTERED base table (service-role) so a just-inserted PENDING row
-- (stripe_item_id IS NULL, stripe_sync_status 'not_added') is visible — the sync
-- must see it to add it to Stripe and stamp it. The client-facing view still
-- hides incomplete / preview rows; this is the engine's read.
--
-- Desired-active = not cancelled and not in a non-billing sync status.
-- 'not_added' = pending add; 'applied' = live — both bill.
-- 'deleted' / 'preview_*' do not.
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
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND mm.stripe_sync_status::text <> ALL(:excluded_statuses)
