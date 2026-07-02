SELECT current_rank_id, gym_id
FROM members
WHERE member_id = CAST(:member_id AS UUID)
