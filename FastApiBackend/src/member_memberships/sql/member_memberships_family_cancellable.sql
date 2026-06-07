-- Live recurring memberships across a paying parent's family (the parent plus
-- accounts linked to it, same gym) that are still billing -- 'applied' and not
-- yet cancelled. The cancellation absorber marks these cancelled in the CRM when
-- Stripe reports the family's subscription gone/cancelled. 'not_added' rows are
-- left to the orphan cleanup; reads the unfiltered base (service-role).
SELECT mm.item_id, mm.member_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mp.plan_id = mm.plan_id AND mp.gym_id = mm.gym_id
JOIN members m
    ON m.member_id = mm.member_id
WHERE mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND mm.stripe_sync_status = 'applied'
  AND mm.gym_id = :gym_id
  AND (
      m.member_id = :parent_member_id
      OR m.account_linked_to_id = :parent_member_id
  )
