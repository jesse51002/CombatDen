-- Store one channel's creator avatar on EVERY pool row of that channel.
--
-- The avatar is a per-CHANNEL property but `video` is a flat per-VIDEO row, so it
-- is duplicated across the channel's videos (~2 each). Keying the write on
-- channel_url — not video_id — is what makes a refresh actually converge: a
-- video-keyed write would fix only the rows the current scrape re-fetched and
-- leave the channel's other rows pointing at a picture URL that has rotated.
--
-- IS DISTINCT FROM makes an unchanged refresh a zero-row write (the common case,
-- since most creators never change their picture), and it is NULL-safe even
-- though the column is NOT NULL DEFAULT ''.
UPDATE video
SET channel_avatar_url = :channel_avatar_url
WHERE channel_url = :channel_url
  AND channel_avatar_url IS DISTINCT FROM :channel_avatar_url;
