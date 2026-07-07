SELECT current_rank_id, current_sub_index, gym_id
FROM members
WHERE member_id = CAST(:member_id AS UUID)
