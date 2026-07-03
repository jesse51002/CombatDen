-- Hard-delete the gym's payer-auth waiver row during pending-gym teardown.
-- Must run AFTER all version rows are deleted
-- (gyms_delete_payer_auth_waiver_versions.sql). Scoped to the payer-auth waiver
-- only so a concurrent normal waiver delete cannot remove this row.
DELETE FROM gym_waivers
WHERE gym_id      = CAST(:gym_id AS UUID)
  AND waiver_type = 'payer_auth';
