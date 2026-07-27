-- The member's MOST RECENT rank change, with BOTH belts already resolved.
--
-- This is what drives the member app's promotion animation. The app shows it
-- once per new promotion, keyed on its own local "promotion watermark" (the
-- same seed-silently-on-null pattern as the celebration watermark), so the
-- server's only job is to answer "what is the member's latest rank change, and
-- what did BOTH belts look like" — the client never has to remember or infer a
-- previous rank.
--
-- The promotion is DECOUPLED from any class. Promotions are staff-driven from
-- the ready-to-promote board, minutes to days after a class and often in bulk,
-- so there is no honest way to attribute one to a specific attendance. Nothing
-- here joins attendance, and the copy the app renders says "You've been
-- promoted", never "that class promoted you".
--
-- Both belts come straight out of the activity's own snapshot (written by
-- src/ranks/sql/insert_rank_activity.sql), NOT from a live join to gym_ranks:
-- image_url and sub_rank_image_overrides are user-writable, so re-uploading
-- belt art must not retroactively change what a past promotion looked like.
--
-- Rows written before the payload carried images simply have no such key, and
-- the ->> operator yields NULL for a missing key exactly as it does for a JSON
-- null — so a legacy row degrades to null images and the client falls back to
-- its themed belt. Nothing is backfilled.
--
-- Scoped by member_id alone, which is already gym-scoped: member_activities
-- carries a composite FK on (member_id, gym_id) into members, and a member row
-- belongs to exactly one gym, so every activity of this member is at this
-- member's gym. The caller has already passed verify_member_self on the path
-- gym.
--
-- LIMIT 1 over a DESC time ordering; activity_id breaks a same-instant tie so
-- the answer is deterministic.
SELECT
    a.activity_id,
    a.time AS promoted_at,
    a.activity_info ->> 'old_rank_name' AS old_rank_name,
    a.activity_info ->> 'new_rank_name' AS new_rank_name,
    a.activity_info ->> 'old_image_url' AS old_image_url,
    a.activity_info ->> 'new_image_url' AS new_image_url
FROM member_activities a
WHERE a.member_id = CAST(:member_id AS UUID)
  AND a.activity_type = 'rank_changed'
ORDER BY a.time DESC, a.activity_id DESC
LIMIT 1;
