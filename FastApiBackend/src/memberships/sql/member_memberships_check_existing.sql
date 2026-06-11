-- ONE member's active/frozen memberships among their requested plans. The
-- check is inherently per-member, so it takes one member_id and batches only
-- across that member's plan ids; returns the conflicting plan_ids.
SELECT plan_id
FROM member_memberships_status
WHERE member_id = :member_id
  AND gym_id    = :gym_id
  AND plan_id   = ANY(:plan_ids)
  AND status IN ('active', 'frozen')
