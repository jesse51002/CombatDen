-- Existing member video-profile rows (one per mood bucket) for a member, used
-- to decide whether the 5 bucket profiles are all present AND fresh enough to
-- skip a rebuild. gym_id (frozen on every row at insert, never changed — see
-- member_profile_upsert.sql) is also read so the caller can verify these
-- profiles actually belong to the gym it's asking about, without a second
-- round-trip.
SELECT bucket, built_at, gym_id
FROM member_video_profile
WHERE member_id = CAST(:member_id AS UUID)
