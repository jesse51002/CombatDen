-- Select the single highest-priority gym that is DUE for a worker run, or no
-- rows when nothing is due. Replaces the old pop-a-queue model: the worker
-- derives its work from timestamps already in the schema rather than an
-- enqueued list.
--
-- A gym (one that has a video spec) is DUE when a trigger is newer than its last
-- run START = MAX(video_run.created_at) of ANY status (a failed run still
-- advances this watermark, so a broken gym does not hot-loop). The trigger
-- decides the priority tier:
--   tier 1  its latest admin_update spec version           (owner/agent edit)
--   tier 2  its latest MANUAL gym_video_feed curation, but only once that
--           curation has settled (>= :curation_batch_hours old), so a burst of
--           removals batches into one run
--   tier 3  its last run is >= :weekly_days old             (periodic refresh)
-- A never-run gym qualifies only via tier 1/2 (an agent-authored spec, or a
-- curation) — a preset-only gym that was never edited is not auto-run (tier 3
-- needs a prior run), matching the old "preset import does not enqueue".
--
-- Gyms already at :gym_run_cap runs within the rolling :cap_window_hours window
-- are excluded (per-gym cap; the system-wide cap is a separate scalar guard the
-- worker checks before this query). Ties within a tier go to the oldest waiting
-- trigger first.
WITH spec_gyms AS (
    SELECT DISTINCT gym_id FROM gym_video_spec
),
last_run AS (
    SELECT gym_id, max(created_at) AS last_run_at
    FROM video_run
    GROUP BY gym_id
),
runs_in_window AS (
    SELECT gym_id, count(*) AS n
    FROM video_run
    WHERE created_at >= now() - make_interval(hours => :cap_window_hours)
    GROUP BY gym_id
),
last_admin AS (
    SELECT gym_id, max(created_at) AS last_admin_at
    FROM gym_video_spec
    WHERE source = 'admin_update'
    GROUP BY gym_id
),
last_curation AS (
    SELECT gym_id, max(curated_at) AS last_curation_at
    FROM gym_video_feed
    WHERE curation_type = 'manual' AND curated_at IS NOT NULL
    GROUP BY gym_id
),
tiered AS (
    SELECT
        g.gym_id,
        lr.last_run_at,
        la.last_admin_at,
        lc.last_curation_at,
        CASE
            WHEN la.last_admin_at IS NOT NULL
                 AND la.last_admin_at
                     > COALESCE(lr.last_run_at, to_timestamp(0))
                THEN 1
            WHEN lc.last_curation_at IS NOT NULL
                 AND lc.last_curation_at
                     > COALESCE(lr.last_run_at, to_timestamp(0))
                 AND lc.last_curation_at
                     <= now() - make_interval(hours => :curation_batch_hours)
                THEN 2
            WHEN lr.last_run_at IS NOT NULL
                 AND lr.last_run_at
                     <= now() - make_interval(days => :weekly_days)
                THEN 3
            ELSE NULL
        END AS tier
    FROM spec_gyms g
    LEFT JOIN last_run lr ON lr.gym_id = g.gym_id
    LEFT JOIN runs_in_window rw ON rw.gym_id = g.gym_id
    LEFT JOIN last_admin la ON la.gym_id = g.gym_id
    LEFT JOIN last_curation lc ON lc.gym_id = g.gym_id
    WHERE COALESCE(rw.n, 0) < :gym_run_cap
)
SELECT gym_id
FROM tiered
WHERE tier IS NOT NULL
ORDER BY
    tier ASC,
    CASE tier
        WHEN 1 THEN last_admin_at
        WHEN 2 THEN last_curation_at
        ELSE last_run_at
    END ASC
LIMIT 1;
