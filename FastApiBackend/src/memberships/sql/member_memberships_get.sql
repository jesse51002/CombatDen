SELECT
    mm.member_id,
    mm.plan_id,
    mm.paid_by_member_id,
    mm.gym_id,
    mp.plan_type,
    mp.duration_unit,
    mp.duration_amount,
    mm.next_due_date,
    mm.cancel_date,
    mm.end_date,
    mm.price_id,
    mpp.stripe_price_id,
    mm.stripe_item_id,
    mm.quantity,
    mpp.price,
    g.timezone
FROM member_memberships mm
JOIN membership_plans mp
  ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
JOIN membership_plan_prices mpp
  ON mm.price_id = mpp.price_id AND mm.gym_id = mpp.gym_id
JOIN gyms g ON g.gym_id = mm.gym_id
-- Authorize the actor as EITHER the membership's subject (self-cancel) OR its
-- payer (cancel a membership you fund for someone else). item_id is the PK, so
-- at most one row matches; the OR only decides whether the actor is allowed to
-- see it. Per-item ops then key off the row's ACTUAL subject member_id (which
-- this query returns), not the actor.
WHERE mm.item_id = :item_id
  AND (mm.member_id = :member_id OR mm.paid_by_member_id = :member_id)
