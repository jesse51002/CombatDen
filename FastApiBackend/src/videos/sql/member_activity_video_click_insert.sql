-- Log a 'video_clicked' member activity when a member opens a video.
-- activity_info carries the clicked video_id + the rec_id it was served under.
--
-- SHARED by both click writers, so the taste-profile read
-- (member_profile_source.sql, which reads only activity_info ->> 'video_id')
-- consumes their rows identically. VideoRecClickService binds a real rec_id;
-- VideoClickService (a member opening a video from the FEED) binds NULL,
-- because nothing recommended that open -- the member chose it. A NULL rec_id
-- renders as a JSON null, which ->> already yields as NULL.
--
-- Append-only for the feed writer -- there is NO conflict target and no dedup:
-- a repeat open is real signal (re-watching a drill means something).
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:activity_type AS member_activity_type),
    jsonb_build_object(
        'video_id', CAST(:video_id AS TEXT), 'rec_id', CAST(:rec_id AS UUID)
    )
)
