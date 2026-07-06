-- Pin a member to a leaf: current_rank_id (the main rank) +
-- current_sub_index (the sub-position, NULL when the rank has no
-- sub-ranks or when unassigning). Both are set together so the
-- count==0 <=> sub_index NULL invariant is enforced by the caller.
UPDATE members
SET current_rank_id = CAST(:new_rank_id AS UUID),
    current_sub_index = CAST(:new_sub_index AS INTEGER)
WHERE member_id = CAST(:member_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
RETURNING member_id, current_rank_id, current_sub_index
