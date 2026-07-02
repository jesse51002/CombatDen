-- Hand-authored migration.
-- Locks class_history and member_attendance to service-role-write-only,
-- matching the class_signups/tasks pattern (see access_rules/class_signups.sql
-- and access_rules/tasks.sql). Both tables are now written exclusively by the
-- service-role backend -- the gated check-in, materialize, and reconciler
-- paths -- so the previous "Gym staff can insert ..." authenticated INSERT
-- policy was a gate-bypass surface: a raw client INSERT with a staff session
-- could append attendance/history rows directly, skipping the capacity /
-- eligibility / points / billing-attribution logic those paths enforce.
-- Removing the policy and widening the REVOKE closes that surface. SELECT
-- policies on both tables are unchanged.
-- Mirrors schemas/access_rules/class_history.sql + member_attendance.sql end
-- state, on top of 20260701000000_class_signups_and_anydate_reschedule.sql.

-- ============================================================
-- class_history: drop authenticated INSERT policy, widen REVOKE
-- ============================================================

DROP POLICY IF EXISTS "Gym staff can insert class history" ON class_history;

REVOKE INSERT, UPDATE, DELETE ON TABLE class_history FROM authenticated;

-- ============================================================
-- member_attendance: drop authenticated INSERT policy, widen REVOKE
-- ============================================================

DROP POLICY IF EXISTS "Gym staff can insert attendance" ON member_attendance;

REVOKE INSERT, UPDATE, DELETE ON TABLE member_attendance FROM authenticated;
