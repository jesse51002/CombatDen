-- Is this video one the gym's feed actually SERVES? Guards the video-scoped
-- click route so a caller cannot log a member activity for an arbitrary,
-- attacker-supplied YouTube id.
--
-- The candidate FROM/JOIN/WHERE core is injected (as the candidate_source
-- variable) from the shared videos_feed_candidate_source.sql -- the single
-- source of "what counts as served" -- so this guard can never drift from the
-- feed the member was actually shown. It binds gym_id + scan_status (supplied
-- by the caller, always 'accepted' here); this file adds only the video filter.
SELECT 1 AS ok
{candidate_source}
  AND v.video_id = CAST(:video_id AS TEXT)
LIMIT 1
