-- Video Engagement (line, count, weekly, all-time).
--
-- Two series over one ISO-week grid (weeks key on the gym-local Monday), from
-- the week of the gym's first served recommendation through the current week:
--   served  - recommendation rows written that week
--   clicked - the subset of those rows the member later opened
--
-- BOTH series bucket on recommended_at, the SERVE time - clicked is NOT
-- bucketed on clicked_at. That is what makes the two lines directly
-- comparable: every click sits in the same bucket as the serve it belongs to,
-- so clicked / served in any week is that week's real click-through rate. If
-- clicks were dated by clicked_at they would drift into later weeks and the
-- ratio between the two lines would mean nothing.
--
-- The consequence is a live tail: the newest week's clicked count can still
-- rise as members open recommendations already served.
--
-- member_video_recs is append-only with one row per SERVE, so a re-serve of
-- the same video is another row and no counter is read.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
recs AS (
    SELECT
        date_trunc(
            'week', (v.recommended_at AT TIME ZONE gd.tz)
        )::date AS week_start,
        (v.clicked_at IS NOT NULL) AS clicked
    FROM member_video_recs v
    CROSS JOIN gym_day gd
    WHERE v.gym_id = CAST(:gym_id AS UUID)
),
bounds AS (
    SELECT
        gd.today,
        (SELECT min(r.week_start) FROM recs r) AS series_start
    FROM gym_day gd
),
weeks AS (
    SELECT gs.week_ts::date AS week_start
    FROM bounds b
    CROSS JOIN generate_series(
        date_trunc('week', b.series_start::timestamp),
        date_trunc('week', b.today::timestamp),
        INTERVAL '1 week'
    ) AS gs(week_ts)
),
points AS (
    SELECT
        wk.week_start,
        (
            SELECT count(*)
            FROM recs r
            WHERE r.week_start = wk.week_start
        )::bigint AS served,
        (
            SELECT count(*)
            FROM recs r
            WHERE r.week_start = wk.week_start
              AND r.clicked
        )::bigint AS clicked
    FROM weeks wk
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'week',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'served',
            'label', 'Served',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.week_start, 'YYYY-MM-DD'),
                            'value', p.served
                        )
                        ORDER BY p.week_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'clicked',
            'label', 'Clicked',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.week_start, 'YYYY-MM-DD'),
                            'value', p.clicked
                        )
                        ORDER BY p.week_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        )
    )
) AS data
