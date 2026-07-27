-- Append a 'rank_changed' audit row for a manual rank change
-- (:activity_type is bound to MemberActivityType.rank_changed). Both display
-- names are Python-derived via rank_display_name(name, sub_rank_type,
-- sub_index) and bound directly (NULL for an unassigned old/new leaf) —
-- the label depends on the gym's sub_rank_type + the sub-index, which
-- SQL can't build, so the name-building joins are gone.
--
-- The payload carries BOTH leaves fully resolved — id, display name,
-- sub-index and belt image on each side — so a reader (the member app's
-- promotion animation) never has to remember or re-derive the belt the
-- member came from. Every value is nullable: the backfill has no "from"
-- leaf, and an unassign has no "to" leaf.
--
-- The two image URLs are SNAPSHOTS, and that is deliberate. gym_ranks.image_url
-- and sub_rank_image_overrides are user-writable, so re-uploading belt art must
-- NOT retroactively change what a past promotion looked like. Each URL is
-- resolved once, at the moment of the change, through the domain's single image
-- rule (RanksBase._leaf_image_url — the leaf's override, else the main rank's
-- image) and frozen here.
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:activity_type AS member_activity_type),
    jsonb_build_object(
        'old_rank_id', CAST(:old_rank_id AS UUID),
        'new_rank_id', CAST(:new_rank_id AS UUID),
        'old_rank_name', CAST(:old_rank_name AS TEXT),
        'new_rank_name', CAST(:new_rank_name AS TEXT),
        'old_sub_index', CAST(:old_sub_index AS INTEGER),
        'new_sub_index', CAST(:new_sub_index AS INTEGER),
        'old_image_url', CAST(:old_image_url AS TEXT),
        'new_image_url', CAST(:new_image_url AS TEXT)
    )
)
