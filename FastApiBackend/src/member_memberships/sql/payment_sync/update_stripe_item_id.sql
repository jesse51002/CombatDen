-- One-time (non-recurring) membership start: stamp the Stripe invoice id AND
-- mark the row live ('applied'). The recurring path flips 'applied' via the
-- sync writeback (PaymentSyncWriteback), but the one-time path runs no sync, so
-- it must flip the status here — otherwise the client-facing member_memberships
-- view (which hides 'not_added') would never surface the purchased membership.
-- This SQL is used ONLY by the one-time start path (member_memberships_start).
UPDATE member_memberships_unfiltered
SET stripe_item_id = :stripe_item_id,
    stripe_sync_status = 'applied'
WHERE item_id   = :item_id
  AND member_id = :member_id
RETURNING *
