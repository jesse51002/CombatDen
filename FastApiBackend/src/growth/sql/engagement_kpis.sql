-- Engagement (kpi_group) - four tiles covering the trailing 30 gym-local days,
-- each compared against the 30 days before them.
--
--   video_ctr       - clicked / served over the recommendations SERVED in the
--                     window (percent; delta is in percentage POINTS)
--   promotions      - rank_changed activity rows in the window
--   points_redeemed - points actually spent: the sum of point_cost over the
--                     redemptions APPROVED in the window
--   redemptions     - how many approved redemptions that was
--
-- Only 'approved' redemptions are counted: a pending request may still be
-- rejected, and a rejected one never cost the member anything. They are
-- bucketed by resolved_at (when staff decided), which is what makes the
-- approval - not the request - the event being measured.
--
-- The 30-day window is the metric's own definition, not tunable behaviour.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
bounds AS (
    SELECT
        gd.tz,
        gd.today,
        gd.today - 30 AS win_start,
        gd.today - 60 AS prev_win_start
    FROM gym_day gd
),
recs AS (
    SELECT
        count(*) FILTER (WHERE r.day > b.win_start)::numeric AS served_now,
        count(*) FILTER (
            WHERE r.day > b.win_start AND r.clicked
        )::numeric AS clicked_now,
        count(*) FILTER (
            WHERE r.day > b.prev_win_start AND r.day <= b.win_start
        )::numeric AS served_prev,
        count(*) FILTER (
            WHERE r.day > b.prev_win_start
              AND r.day <= b.win_start
              AND r.clicked
        )::numeric AS clicked_prev
    FROM (
        SELECT
            (v.recommended_at AT TIME ZONE bb.tz)::date AS day,
            (v.clicked_at IS NOT NULL) AS clicked
        FROM member_video_recs v
        CROSS JOIN bounds bb
        WHERE v.gym_id = CAST(:gym_id AS UUID)
          AND (v.recommended_at AT TIME ZONE bb.tz)::date > bb.prev_win_start
    ) r
    CROSS JOIN bounds b
),
promos AS (
    SELECT
        count(*) FILTER (WHERE a.day > b.win_start)::bigint AS promos_now,
        count(*) FILTER (
            WHERE a.day > b.prev_win_start AND a.day <= b.win_start
        )::bigint AS promos_prev
    FROM (
        SELECT (act."time" AT TIME ZONE bb.tz)::date AS day
        FROM member_activities act
        CROSS JOIN bounds bb
        WHERE act.gym_id = CAST(:gym_id AS UUID)
          AND act.activity_type = 'rank_changed'
          AND (act."time" AT TIME ZONE bb.tz)::date > bb.prev_win_start
    ) a
    CROSS JOIN bounds b
),
redemptions AS (
    SELECT
        count(*) FILTER (WHERE x.day > b.win_start)::bigint AS redeemed_now,
        count(*) FILTER (
            WHERE x.day > b.prev_win_start AND x.day <= b.win_start
        )::bigint AS redeemed_prev,
        COALESCE(
            sum(x.point_cost) FILTER (WHERE x.day > b.win_start), 0
        )::bigint AS points_now,
        COALESCE(
            sum(x.point_cost) FILTER (
                WHERE x.day > b.prev_win_start AND x.day <= b.win_start
            ), 0
        )::bigint AS points_prev
    FROM (
        SELECT
            (rr.resolved_at AT TIME ZONE bb.tz)::date AS day,
            rr.point_cost
        FROM member_reward_redemptions rr
        CROSS JOIN bounds bb
        WHERE rr.gym_id = CAST(:gym_id AS UUID)
          AND rr.status = 'approved'
          AND rr.resolved_at IS NOT NULL
          AND (rr.resolved_at AT TIME ZONE bb.tz)::date > bb.prev_win_start
    ) x
    CROSS JOIN bounds b
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'video_ctr',
            'label', 'Video Click Rate',
            'value', COALESCE(
                round(rc.clicked_now / NULLIF(rc.served_now, 0) * 100, 1), 0
            ),
            'unit', 'percent',
            'delta_abs', CASE
                WHEN rc.served_now > 0 AND rc.served_prev > 0
                    THEN round(
                        rc.clicked_now / rc.served_now * 100
                        - rc.clicked_prev / rc.served_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'promotions',
            'label', 'Promotions',
            'value', pr.promos_now,
            'unit', 'count',
            'delta_abs', pr.promos_now - pr.promos_prev,
            'delta_pct', CASE
                WHEN pr.promos_prev > 0
                    THEN round(
                        (pr.promos_now - pr.promos_prev)::numeric
                        / pr.promos_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'points_redeemed',
            'label', 'Points Redeemed',
            'value', rd.points_now,
            'unit', 'count',
            'delta_abs', rd.points_now - rd.points_prev,
            'delta_pct', CASE
                WHEN rd.points_prev > 0
                    THEN round(
                        (rd.points_now - rd.points_prev)::numeric
                        / rd.points_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'redemptions',
            'label', 'Reward redemptions',
            'value', rd.redeemed_now,
            'unit', 'count',
            'delta_abs', rd.redeemed_now - rd.redeemed_prev,
            'delta_pct', CASE
                WHEN rd.redeemed_prev > 0
                    THEN round(
                        (rd.redeemed_now - rd.redeemed_prev)::numeric
                        / rd.redeemed_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        )
    )
) AS data
FROM recs rc
CROSS JOIN promos pr
CROSS JOIN redemptions rd
