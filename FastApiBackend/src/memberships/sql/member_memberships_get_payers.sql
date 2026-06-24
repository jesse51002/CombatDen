-- The payer of each membership row in a batch (immutable, so safe to read
-- before locking). Reads the unfiltered base (service-role): pending rows
-- have a payer too. Backs the multi-item cancel/preview lock-key resolution.
SELECT item_id,
       paid_by_member_id
FROM member_memberships_unfiltered
WHERE item_id = ANY(CAST(:item_ids AS UUID[]))
