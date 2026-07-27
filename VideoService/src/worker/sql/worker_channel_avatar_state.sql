-- Which of these channels already have an avatar stored anywhere in the pool.
--
-- Drives the scrape avatar pass's uncovered-first ordering: when the per-run call
-- cap binds, a channel with NO avatar at all must be resolved before the cap is
-- spent REFRESHING one that already has a (probably still valid) picture.
-- Aggregated per channel because the avatar is duplicated across the channel's
-- video rows — any one row carrying it means the channel is covered.
SELECT channel_url,
       bool_or(channel_avatar_url <> '') AS has_avatar
FROM video
WHERE channel_url = ANY(:channel_urls)
GROUP BY channel_url;
