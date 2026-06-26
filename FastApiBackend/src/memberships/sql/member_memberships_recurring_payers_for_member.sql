-- The DISTINCT payers billing MEMBER_ID's live recurring memberships — the
-- subscriptions a freeze/unfreeze of this member (as the SUBJECT) must
-- re-converge: the member's lines drop from / return to each payer's sub.
-- Scoped to the member as subject (member_id), across however many payers fund
-- their memberships. Reads the unfiltered base (service-role) so a pending
-- (not_added) row's payer is included; cancelled / deleted / preview rows are
-- not a live billing relationship and are excluded.
SELECT DISTINCT mm.paid_by_member_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.member_id = :member_id
  AND mm.gym_id = :gym_id
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND mm.stripe_sync_status IN ('applied', 'not_added')
