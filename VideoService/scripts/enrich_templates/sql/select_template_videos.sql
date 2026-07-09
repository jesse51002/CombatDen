-- Every DISTINCT video referenced by the template feeds (video_gym_feed — the 76
-- demo templates), BOTH verdicts ('good' AND 'rejected'), joined to the shared
-- pool for the fields the enrich call needs. This is the target set the one-time
-- enrich-templates run summarises + embeds into the RAG sidecar. Because these
-- video_ids are exactly the pool videos a preset import copies into a real gym's
-- feed, seeding their video_rag rows makes preset imports serve instantly (and,
-- since video_rag is shared by video_id, enriches every gym that imports a preset
-- for free). The JOIN keeps it FK-safe (only pooled videos). ORDER BY gives a
-- deterministic pass so a resumed run skips exactly what the sidecar already holds.
SELECT DISTINCT
    v.video_id,
    v.title,
    v.channel_name,
    v.description,
    v.thumbnail_url,
    v.duration_seconds,
    v.transcript
FROM video_gym_feed f
JOIN video v ON v.video_id = f.video_id
ORDER BY v.video_id;
