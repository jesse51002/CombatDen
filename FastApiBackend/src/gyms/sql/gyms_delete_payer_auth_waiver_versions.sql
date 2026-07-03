-- Delete all version rows for the gym's payer-auth waiver during pending-gym
-- teardown. Must run AFTER current_version_id has been NULLed out
-- (gyms_null_payer_auth_waiver_current_version.sql) and BEFORE deleting the
-- waiver row itself (gyms_delete_payer_auth_waiver.sql).
DELETE FROM gym_waiver_versions
WHERE waiver_id IN (
    SELECT waiver_id
    FROM gym_waivers
    WHERE gym_id      = CAST(:gym_id AS UUID)
      AND waiver_type = 'payer_auth'
);
