-- Read the family's CANCELLED recurring memberships that still carry a Stripe
-- line id and are not yet marked deleted — the candidates the writeback checks
-- against the live subscription to confirm removal and stamp 'deleted'. Reads the
-- unfiltered base table (service-role).
SELECT
    mm.item_id,
    mm.member_id,
    mm.stripe_item_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.member_id = ANY(:member_ids)
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NOT NULL
  AND mm.stripe_item_id IS NOT NULL
  AND (mm.stripe_sync_status IS NULL OR mm.stripe_sync_status <> 'deleted')
