-- SYSTEM writeback (service-role): stamp 'deleted' on cancelled membership rows
-- the sync confirmed are gone from the live subscription. The cancel already
-- removed the line from Stripe; this records that Stripe is in sync, so a
-- cancelled row can never be mistaken for one still billing.
UPDATE member_memberships_unfiltered
SET stripe_sync_status = 'deleted'
WHERE item_id = ANY(:item_ids)
