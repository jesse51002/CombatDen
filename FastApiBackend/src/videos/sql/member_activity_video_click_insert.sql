-- Log a 'video_clicked' member activity when a member opens a rec. activity_info
-- carries the clicked video_id + the rec_id it was served under.
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:activity_type AS member_activity_type),
    jsonb_build_object('video_id', :video_id, 'rec_id', CAST(:rec_id AS UUID))
)
