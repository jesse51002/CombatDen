-- Drop rows for metrics the registry no longer defines. Run after a gym's
-- compute loop so a retired key stops being served the moment it is removed
-- from the registry, with no migration.
DELETE FROM gym_growth_metrics
WHERE gym_id = CAST(:gym_id AS UUID)
  AND key <> ALL (CAST(:keys AS TEXT[]))
