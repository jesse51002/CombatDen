-- SYSTEM writeback (service-role): stamp the sync result onto one membership row
-- after Stripe converged. Sets the Stripe line id (NULL -> value on first sync —
-- echoing the same value is a no-op the immutable trigger allows), the
-- next_due_date from the line's current-period end, and the sync status to
-- 'applied' (this row is live on Stripe). Writes the unfiltered base table.
UPDATE member_memberships_unfiltered
SET stripe_item_id = :stripe_item_id,
    next_due_date = :next_due_date,
    stripe_sync_status = 'applied'
WHERE item_id = :item_id
  AND member_id = :member_id
