-- ONE member's active/frozen RECURRING memberships among their requested plans.
-- Only RECURRING plans count as a conflict: recurring stays one-active-per-plan
-- (the trg_recurring_no_active_memberships DB trigger is the backstop), while
-- one_time / trial packs are allowed to STACK — a member may hold several of the
-- same pack at once, or buy another before the first is used up. The check is
-- inherently per-member, so it takes one member_id and batches only across that
-- member's plan ids; returns the conflicting plan_ids.
SELECT mms.plan_id
FROM member_memberships_status mms
JOIN membership_plans mp
  ON mp.plan_id = mms.plan_id
 AND mp.gym_id = mms.gym_id
WHERE mms.member_id = :member_id
  AND mms.gym_id    = :gym_id
  AND mms.plan_id   = ANY(:plan_ids)
  AND mms.status IN ('active', 'frozen')
  AND mp.plan_type = 'recurring'
