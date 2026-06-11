-- Pure relationship change. The member's own billing state (card, payment
-- method, freeze window, sub id) is per-PAYER state and survives linking —
-- a linked member may self-pay (member_memberships.paid_by_member_id), so
-- linking must never wipe their billing identity.
UPDATE members
SET account_linked_to_id = :parent_member_id
WHERE member_id = :member_id
RETURNING member_id
