-- PASS 1 targets: every DISTINCT legacy `@handle`-form channel in the pool, with
-- a few of its video ids as representatives.
--
-- The legacy `videos/` YAML pool stored the weak handle-form channel_url
-- (`youtube.com/@handle`), which carries NO channel id — so the avatar lookup
-- (`channels.list?id=`) cannot address it. A handle uniquely identifies one
-- channel, so ONE of that channel's videos is enough to recover the id via
-- `videos.list?id=<video_id>` → `snippet.channelId`. Grouping here rather than
-- listing every handle-form ROW is what makes pass 1 cost ~231 calls instead of
-- ~457: the work is per channel, not per video.
--
-- Several representatives are returned because a single one may have been deleted
-- or made private since the scrape, in which case the API returns no item for it;
-- the backfill retries such channels with their next representative.
--
-- Resumable by construction: a channel whose URL has already been upgraded to the
-- id form no longer matches, so a re-run picks up exactly what is left.
SELECT channel_url,
       ARRAY_AGG(video_id ORDER BY video_id) AS video_ids
FROM video
WHERE channel_url LIKE '%/@%'
GROUP BY channel_url
ORDER BY channel_url;
