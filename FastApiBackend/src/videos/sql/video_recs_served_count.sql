-- How many recommendations this member has been served (all categories). The
-- rec service takes this COUNT modulo the rotation length to pick which genre
-- category to serve next, so the served category advances by one each call.
-- member_video_recs is an append-only serve log (one row per serve).
SELECT COUNT(*) AS n
FROM member_video_recs
WHERE member_id = CAST(:member_id AS UUID)
