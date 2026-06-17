-- Live recurring memberships a PAYER is billing (every row whose
-- paid_by_member_id is this payer, same gym) that are still on Stripe --
-- 'applied' and not yet cancelled. PaymentSyncCancel marks these cancelled in
-- the CRM when the sync finds the payer's subscription gone/cancelled; rows
-- paid by OTHER payers in the same family are untouched (their subs are alive).
-- 'not_added' rows are left to the orphan cleanup; reads the unfiltered base
-- (service-role).
SELECT mm.item_id, mm.member_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mp.plan_id = mm.plan_id AND mp.gym_id = mm.gym_id
WHERE mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND mm.stripe_sync_status = 'applied'
  AND mm.gym_id = :gym_id
  AND mm.paid_by_member_id = :payer_member_id
