-- Live recurring memberships funded across ONE authorization pair: the payee
-- (member_id) whose memberships are paid by the payer (paid_by_member_id),
-- still 'applied' on Stripe and not yet cancelled. Pair-scoped (only this
-- relationship's memberships) — backs the remove-authorization preview + the
-- cascading cancel. Reads the unfiltered base (service-role).
SELECT mm.item_id,
       mm.member_id,
       mp.plan_name,
       mm.total_price
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mp.plan_id = mm.plan_id AND mp.gym_id = mm.gym_id
WHERE mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND mm.stripe_sync_status = 'applied'
  AND mm.member_id = :member_id
  AND mm.paid_by_member_id = :payer_member_id
ORDER BY mp.plan_name
