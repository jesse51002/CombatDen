DELETE FROM gym_video_feed WHERE gym_id = CAST(:gym_id AS UUID)
