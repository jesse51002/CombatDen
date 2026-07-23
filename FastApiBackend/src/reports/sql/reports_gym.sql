-- The gym facts both report paths need: the name (for the download filename
-- slug) and the IANA timezone (for the gym-local month window + local
-- datetime rendering).
SELECT
    g.gym_name,
    g.timezone
FROM gyms g
WHERE g.gym_id = CAST(:gym_id AS UUID)
