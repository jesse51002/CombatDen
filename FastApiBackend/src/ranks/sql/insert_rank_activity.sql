-- Append a 'rank_changed' audit row for a manual rank change
-- (:activity_type is bound to RANK_CHANGED_ACTIVITY_TYPE).
-- Rank names are resolved by LEFT JOIN so an unassigned (NULL) old or
-- new rank simply yields a null name. The (SELECT 1) anchor keeps the
-- single INSERT row even when both joins miss.
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
SELECT
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    :activity_type,
    jsonb_build_object(
        'old_rank_id', old_r.rank_id,
        'new_rank_id', new_r.rank_id,
        'old_rank_name',
            NULLIF(TRIM(COALESCE(old_r.main_name, '') || ' '
                       || COALESCE(old_r.sub_name, '')), ''),
        'new_rank_name',
            NULLIF(TRIM(COALESCE(new_r.main_name, '') || ' '
                       || COALESCE(new_r.sub_name, '')), '')
    )
FROM (SELECT 1) AS anchor
LEFT JOIN gym_ranks old_r ON old_r.rank_id = CAST(:old_rank_id AS UUID)
LEFT JOIN gym_ranks new_r ON new_r.rank_id = CAST(:new_rank_id AS UUID)
