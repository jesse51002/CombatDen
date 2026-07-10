-- Append a 'rank_changed' audit row for a manual rank change
-- (:activity_type is bound to MemberActivityType.rank_changed). Both display
-- names are Python-derived via rank_display_name(name, sub_rank_type,
-- sub_index) and bound directly (NULL for an unassigned old/new leaf) —
-- the label depends on the gym's sub_rank_type + the sub-index, which
-- SQL can't build, so the name-building joins are gone.
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:activity_type AS member_activity_type),
    jsonb_build_object(
        'old_rank_id', CAST(:old_rank_id AS UUID),
        'new_rank_id', CAST(:new_rank_id AS UUID),
        'old_rank_name', CAST(:old_rank_name AS TEXT),
        'new_rank_name', CAST(:new_rank_name AS TEXT)
    )
)
