-- The payer of one membership row (immutable, so safe to read before locking).
-- Reads the unfiltered base (service-role): pending rows have a payer too.
SELECT paid_by_member_id
FROM member_memberships_unfiltered
WHERE item_id = :item_id
