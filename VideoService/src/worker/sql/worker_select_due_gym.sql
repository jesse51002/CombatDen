-- Select the single highest-priority gym that is DUE for a worker run, or no
-- rows when nothing is due. Replaces the old pop-a-queue model: the worker
-- derives its work from timestamps already in the schema rather than an
-- enqueued list.
--
-- A gym (one that has a video spec) is DUE when a trigger is newer than the
-- relevant last-run watermark. The trigger decides the priority tier:
--   tier 1  its latest admin_update spec version, newer than the last COMPLETED
--           run (owner/agent edit) — a FAILED run must NOT suppress this: a
--           transient scrape error that failed the run should be retried, not
--           swallowed until the weekly refresh, so tier 1 compares against the
--           last run that actually completed. The rolling run caps (per-gym 2/24h,
--           system 5/24h, counting runs of ANY status) are what bound a
--           persistently-broken gym instead — it can retry a couple of times, then
--           waits for the window to roll. A gym whose scrape keeps failing thus
--           cannot hot-loop, while a gym whose scrape transiently failed re-runs
--           promptly.
--   tier 3  its last run of ANY status is >= :weekly_days old (periodic refresh) —
--           a failed run DOES advance this watermark (the anti-hot-loop guard for
--           the periodic tier; the caps also apply).
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
-- The tier-1 watermark: the last run that actually COMPLETED. A failed run is not
-- here, so it never suppresses an admin_update trigger (see the header note).
last_completed_run AS (
    SELECT gym_id, max(created_at) AS last_completed_at
    FROM video_run
    WHERE status = 'completed'
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
            -- tier 1 fires when the admin edit is newer than the last COMPLETED
            -- run (a failed run does not count), so a failed scrape is retried.
            WHEN la.last_admin_at IS NOT NULL
                 AND la.last_admin_at
                     > COALESCE(lcr.last_completed_at, to_timestamp(0))
                THEN 1
            WHEN lr.last_run_at IS NOT NULL
                 AND lr.last_run_at
                     <= now() - make_interval(days => :weekly_days)
                THEN 3
            ELSE NULL
        END AS tier
    FROM spec_gyms g
    LEFT JOIN last_run lr ON lr.gym_id = g.gym_id
    LEFT JOIN last_completed_run lcr ON lcr.gym_id = g.gym_id
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
