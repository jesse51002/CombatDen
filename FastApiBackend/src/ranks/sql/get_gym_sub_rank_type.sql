SELECT sub_rank_type
FROM gyms
WHERE gym_id = CAST(:gym_id AS UUID)
