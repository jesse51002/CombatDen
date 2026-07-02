-- The gym's IANA timezone: frozen onto each imported class's schedule version
-- and used to convert each expanded local class time to a UTC occurred_at
-- (via ClassesExpander) when seeding past attendance.
SELECT timezone FROM gyms WHERE gym_id = CAST(:gym_id AS UUID)
