-- THE unified real-gym video feed page. ONE query serves the whole feed and
-- backs the member rec: it ALWAYS merges the owner "Your videos" section with
-- the gym's latest COMPLETED run, serves ONLY enriched-AND-accepted videos
-- (INNER JOIN video_rag), and ranks on a single axis with an owner boost and a
-- decayed already-watched penalty. There is no owner/source param — the owner
-- rows and the run rows are one candidate set.
--
-- Parameters:
--   :gym_id             UUID of the gym
--   :scan_status        'accepted' | 'rejected'  (gym_video_scan_status enum)
--   :video_type         a single video_genre string or NULL (exact tag match)
--   :filter_big_group   'educational' | 'entertainment' | NULL (big-group filter)
--   :educational_genres list[str]  the genre strings that map to EDUCATIONAL
--   :member_embedding   the member's taste embedding (pgvector text form) or NULL
--   :member_id          the member (UUID) whose watch history decays the penalty,
--                       or NULL (no penalty)
--   :bump_fraction      owner boost / watch penalty as a fraction of the axis's
--                       sample stddev (sigma)
--   :half_life_seconds  half-life (seconds) of the per-serve watch penalty
--   :limit              page size
--   :offset             0-based start index
--
-- Ranking:
--   axis          cosine distance to the member embedding when one is bound,
--                 gym relevance_index otherwise.
--   sigma         sample stddev of axis over the whole candidate set (window).
--   penalty_units cumulative, recency-decayed count of prior serves of this
--                 video to this member (a just-served video ≈ 1, an old one ≈ 0);
--                 0 rows when :member_id is NULL.
--   adjusted      axis, owner videos nudged NEARER by bump_fraction*sigma and
--                 watched videos nudged FARTHER by penalty_units*bump_fraction*
--                 sigma. Lower sorts first.
--
-- NOTE: COUNT(*) OVER() returns 0 rows (and therefore total=0) when the
-- requested offset is beyond the last matching row.
WITH candidates AS (
    SELECT
        v.video_id,
        v.url,
        v.title,
        v.description,
        v.thumbnail_url,
        v.channel_name,
        v.channel_url,
        v.channel_avatar_url,
        v.view_count,
        v.like_count,
        v.duration_seconds,
        v.tag,
        v.disciplines AS gym_type,
        v.source_queries,
        v.relevance_index,
        v.transcript_error,
        v.transcript,
        (f.video_run_id IS NULL) AS owner_added,
        CASE
            WHEN CAST(:member_embedding AS text) IS NULL THEN v.relevance_index
            ELSE (r.embedding <=> CAST(:member_embedding AS vector))
        END AS axis,
        COALESCE((
            SELECT SUM(power(
                0.5,
                EXTRACT(epoch FROM now() - mr.recommended_at)
                    / CAST(:half_life_seconds AS double precision)
            ))
            FROM member_video_recs mr
            WHERE mr.member_id = CAST(:member_id AS UUID)
              AND mr.video_id = v.video_id
        ), 0) AS penalty_units
    FROM gym_video_feed f
    JOIN video v ON v.video_id = f.video_id
    JOIN video_rag r ON r.video_id = v.video_id
    WHERE f.gym_id = CAST(:gym_id AS UUID)
      AND f.scan_status = CAST(:scan_status AS gym_video_scan_status)
      AND (
        f.video_run_id IS NULL
        -- Serve the latest COMPLETED run only: a mid-flight 'running' run must
        -- never become "latest" or the feed would blank until it finishes.
        OR f.video_run_id = (
            SELECT run_id FROM video_run
            WHERE gym_id = CAST(:gym_id AS UUID)
              AND status = 'completed'
            ORDER BY created_at DESC
            LIMIT 1)
      )
      AND (
        CAST(:video_type AS text) IS NULL
        OR v.tag::text = CAST(:video_type AS text)
      )
      AND (
        CAST(:filter_big_group AS text) IS NULL
        OR (
          CAST(:filter_big_group AS text) = 'educational'
          AND v.tag IS NOT NULL
          AND v.tag::text = ANY(:educational_genres)
        )
        OR (
          CAST(:filter_big_group AS text) = 'entertainment'
          AND v.tag IS NOT NULL
          AND NOT (v.tag::text = ANY(:educational_genres))
        )
      )
),
ranked AS (
    SELECT
        candidates.*,
        COALESCE(stddev_samp(axis) OVER (), 0) AS sigma,
        COUNT(*) OVER() AS total
    FROM candidates
)
SELECT
    video_id,
    url,
    title,
    description,
    thumbnail_url,
    channel_name,
    channel_url,
    channel_avatar_url,
    view_count,
    like_count,
    duration_seconds,
    tag,
    gym_type,
    source_queries,
    relevance_index,
    transcript_error,
    transcript,
    owner_added,
    total
FROM ranked
ORDER BY
    (
        axis
        - (CASE WHEN owner_added THEN 1 ELSE 0 END)
            * CAST(:bump_fraction AS double precision) * sigma
        + penalty_units
            * CAST(:bump_fraction AS double precision) * sigma
    ) ASC,
    relevance_index ASC,
    video_id ASC
LIMIT :limit OFFSET :offset
