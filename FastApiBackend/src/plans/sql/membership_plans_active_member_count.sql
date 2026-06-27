-- Soft-delete guard: count the plan's members with a LIVE (active) membership.
-- A plan with members can't be deleted — their billing references it; move
-- them off first. Mirrors the enrolled_count the CRM grays its Delete button
-- on (member_memberships_status.status = 'active').
SELECT count(*) AS active_count
FROM member_memberships_status mms
WHERE mms.plan_id = :plan_id
  AND mms.gym_id  = :gym_id
  AND mms.status  = 'active'
