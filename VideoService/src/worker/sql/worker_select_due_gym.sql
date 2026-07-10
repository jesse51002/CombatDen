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
--   tier 3  its last run is >= :weekly_days old             (periodic refresh)
-- A never-run gym qualifies only via tier 1 (an agent-authored spec) — a
-- preset-only gym that was never edited is not auto-run (tier 3 needs a prior
-- run), matching the old "preset import does not enqueue". A manual gym_video_feed
-- curation does not trigger a scrape run.
--
-- Gyms already at :gym_run_cap runs within the rolling :cap_window_hours window
-- are excluded (per-gym cap; the system-wide cap is a separate scalar guard the
-- worker checks before this query). A gym with an in-flight ('running') run is
-- ALSO excluded — only the scrape step opens runs, and a gym must never have two
-- in-flight runs at once (the second would race the finalize/serve logic). Ties
-- within a tier go to the oldest waiting trigger first.
WITH spec_gyms AS (
    SELECT DISTINCT gym_id FROM gym_video_spec
),
running_gyms AS (
    SELECT DISTINCT gym_id FROM video_run WHERE status = 'running'
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
tiered AS (
    SELECT
        g.gym_id,
        lr.last_run_at,
        la.last_admin_at,
        CASE
            WHEN la.last_admin_at IS NOT NULL
                 AND la.last_admin_at
                     > COALESCE(lr.last_run_at, to_timestamp(0))
                THEN 1
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
    WHERE COALESCE(rw.n, 0) < :gym_run_cap
      AND g.gym_id NOT IN (SELECT gym_id FROM running_gyms)
)
SELECT gym_id
FROM tiered
WHERE tier IS NOT NULL
ORDER BY
    tier ASC,
    CASE tier
        WHEN 1 THEN last_admin_at
        ELSE last_run_at
    END ASC
LIMIT 1;
