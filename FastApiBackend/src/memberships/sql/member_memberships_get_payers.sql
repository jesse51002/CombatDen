-- The payer of each membership row in a batch (immutable, so safe to read
-- before locking). Reads the unfiltered base (service-role): pending rows
-- have a payer too. Backs the multi-item cancel/preview lock-key resolution.
-- Scoped to items the actor is entitled to — its OWN (member_id) or ones it
-- PAYS for (paid_by_member_id) — exactly the subject-or-payer rule
-- member_memberships_get.sql enforces. So an item_id the actor isn't authorized
-- for is excluded here, failing the caller's "every item must resolve" check
-- BEFORE the billing lock is taken (it never locks an unrelated payer's sub).
SELECT item_id,
       paid_by_member_id
FROM member_memberships_unfiltered
WHERE item_id = ANY(CAST(:item_ids AS UUID[]))
  AND (member_id = :member_id OR paid_by_member_id = :member_id)
