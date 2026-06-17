-- Of the given Stripe subscription-item ids, the ones mapped to a LIVE membership
-- (stripe_sync_status 'applied' or 'migrating' — the row is on Stripe, billing).
-- A 'deleted' row is NOT a live link (its line should be gone from Stripe), and
-- the filtered member_memberships view does NOT hide 'deleted' — so the orphan
-- sweep reads the unfiltered base with an explicit status filter. A subscription
-- none of whose item ids appear here has no live DB linkage and is an orphan to
-- cancel. stripe_item_id (si_...) is globally unique, so no gym scoping is needed
-- (this also handles the shared-test-account case where gyms share one account).
SELECT stripe_item_id
FROM member_memberships_unfiltered
WHERE stripe_item_id = ANY(:stripe_item_ids)
  AND stripe_sync_status IN ('applied', 'migrating')
