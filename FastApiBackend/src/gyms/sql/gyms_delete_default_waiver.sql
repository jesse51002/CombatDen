-- Hard-delete the gym's default waiver row during pending-gym teardown.
-- Must run AFTER all version rows are deleted
-- (gyms_delete_default_waiver_versions.sql). Scoped to the default waiver
-- only so a concurrent normal waiver delete cannot remove this row.
DELETE FROM gym_waivers
WHERE gym_id     = CAST(:gym_id AS UUID)
  AND is_default = TRUE;
