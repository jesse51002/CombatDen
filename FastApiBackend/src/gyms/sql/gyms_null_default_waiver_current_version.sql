-- NULL out current_version_id on the gym's default waiver during pending-gym
-- teardown. Breaks the forward FK cycle (gym_waivers.current_version_id →
-- gym_waiver_versions) so version rows can be deleted next without a FK
-- violation. Scoped to the default waiver to avoid touching other waivers.
UPDATE gym_waivers
   SET current_version_id = NULL
 WHERE gym_id     = CAST(:gym_id AS UUID)
   AND is_default = TRUE;
