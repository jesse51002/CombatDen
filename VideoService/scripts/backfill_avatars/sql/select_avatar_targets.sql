-- PASS 2 targets: every DISTINCT canonical `/channel/UC…` channel that still has
-- at least one pool row without an avatar.
--
-- `bool_or(channel_avatar_url = '')` (not `bool_and`) so a channel that is only
-- PARTLY covered still shows up — that happens when the backend's owner-added
-- path filled the avatar for one video of a channel the scrape also pooled.
--
-- `known_avatar` is the avatar some other row of the same channel already holds
-- (MAX over the group; '' sorts below any real URL). When it is non-empty the
-- backfill copies it across the channel's rows and spends NO quota — the avatar is
-- a per-channel property, so one row knowing it is enough.
--
-- Handle-form rows are deliberately excluded: pass 1 upgrades them to the id form
-- first, so they enter this target set on the same run.
--
-- Resumable by construction: a fully covered channel no longer matches.
SELECT channel_url,
       MAX(channel_avatar_url) AS known_avatar
FROM video
WHERE channel_url LIKE '%/channel/%'
GROUP BY channel_url
HAVING bool_or(channel_avatar_url = '')
ORDER BY channel_url;
