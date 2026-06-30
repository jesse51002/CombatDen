-- The gym's IANA timezone, used to convert each expanded local class time to a
-- UTC occurred_at (via ClassesExpander) when seeding past class_history.
SELECT timezone FROM gyms WHERE gym_id = CAST(:gym_id AS UUID)
