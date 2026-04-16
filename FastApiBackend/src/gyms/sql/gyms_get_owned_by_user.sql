-- Look up the gym owned by the authenticated user.
-- Reads the filtered ``gyms`` view (not ``gyms_unfiltered``) so
-- rows whose Stripe linkage has been cleared on a read-side 404
-- are invisible to both the create pre-check and the status
-- refresh — the user can recreate cleanly instead of being
-- deadlocked by a 409 on the orphan row.
-- ORDER BY e.created_at DESC defends against the edge case
-- where a user ended up with multiple owner rows after a
-- clear-and-recreate cycle: the newest owner wins.
SELECT g.gym_id,
       g.gym_name,
       g.stripe_account_id,
       g.stripe_onboarding_status
FROM gyms g
JOIN gym_employees e ON e.gym_id = g.gym_id
WHERE e.user_id = :user_id
  AND e.employee_type = 'owner'
ORDER BY e.created_at DESC
LIMIT 1;
