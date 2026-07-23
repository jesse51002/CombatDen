-- Members Over Time (line, count, monthly, all-time) + companion table.
--
-- THE LINE: one series, one point per gym-local month from the month of the
-- gym's first membership through the current month. A month's value is the
-- number of members who held a live membership as of that month's last day and
-- had not yet crossed into dormancy by then - the same canonical rule the KPI
-- tiles and the churn line use, evaluated against a historical date instead of
-- today.
--
-- THE COMPANION TABLE (stacked under the line): one row per the SAME month
-- grid, breaking the movement down into
--   Gained    - members whose FIRST membership started in the month
--   Lost      - members who crossed into dormancy in the month (the canonical
--               members_gained_lost "lost" rule)
--   Retained  - members present (live, non-dormant) when the month OPENED who
--               were still present at its end: active at month-open and not
--               lost during the month. Mirrors churn_trend's "base" (first
--               membership strictly before the month, not yet dormant as it
--               opened) minus those lost during the month.
--   Trial     - distinct members holding a trial-plan membership that OVERLAPPED
--               the month (active on at least its first day) - the active-trial
--               population for the month.
WITH
{dormant_cte},
bounds AS (
    SELECT
        gd.today,
        COALESCE(
            (SELECT min(d.first_start) FROM member_dormancy d),
            gd.today
        ) AS series_start
    FROM gym_day gd
),
months AS (
    SELECT
        gs.month_ts::date AS month_start,
        (gs.month_ts + INTERVAL '1 month' - INTERVAL '1 day')::date
            AS month_end,
        (gs.month_ts + INTERVAL '1 month')::date AS next_month_start
    FROM bounds b
    CROSS JOIN generate_series(
        date_trunc('month', b.series_start::timestamp),
        date_trunc('month', b.today::timestamp),
        INTERVAL '1 month'
    ) AS gs(month_ts)
),
metrics AS (
    SELECT
        mo.month_start,
        -- Line series: members active as of the month's last day.
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= mo.month_end
              AND (NOT d.dormant OR d.dormant_since > mo.month_end)
        )::bigint AS active,
        -- Gained: first membership started in the month.
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.first_start >= mo.month_start
              AND d.first_start < mo.next_month_start
        )::bigint AS gained,
        -- Lost: crossed into dormancy during the month.
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.dormant
              AND d.dormant_since >= mo.month_start
              AND d.dormant_since < mo.next_month_start
        )::bigint AS lost,
        -- Retained: active when the month OPENED (first membership strictly
        -- before it, not yet dormant) and NOT lost during the month.
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.first_start IS NOT NULL
              AND d.first_start < mo.month_start
              AND (NOT d.dormant OR d.dormant_since >= mo.next_month_start)
        )::bigint AS retained,
        -- Trial: distinct members with a trial-plan membership overlapping the
        -- month. Reads the shared membership_terms rows (gym-scoped, carrying
        -- plan_type + the LEAST(cancel,end) term date) so the trial definition
        -- can never drift from the dormancy fragment's term logic.
        (
            SELECT count(DISTINCT t.member_id)
            FROM membership_terms t
            WHERE t.plan_type = 'trial'
              AND t.start_date <= mo.month_end
              AND (t.term_date IS NULL OR t.term_date >= mo.month_start)
        )::bigint AS trial
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'active',
            'label', 'Active Members',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(m.month_start, 'YYYY-MM-DD'),
                            'value', m.active
                        )
                        ORDER BY m.month_start
                    )
                    FROM metrics m
                ),
                '[]'::jsonb
            )
        )
    ),
    'table', jsonb_build_object(
        'orientation', 'stacked',
        'columns', jsonb_build_array(
            jsonb_build_object('key', 'month', 'label', 'Month', 'type', 'date'),
            jsonb_build_object(
                'key', 'gained', 'label', 'Gained', 'type', 'number',
                'tone', 'good'
            ),
            jsonb_build_object(
                'key', 'lost', 'label', 'Lost', 'type', 'number',
                'tone', 'bad'
            ),
            jsonb_build_object(
                'key', 'retained', 'label', 'Retained', 'type', 'number',
                'tone', 'warn'
            ),
            jsonb_build_object(
                'key', 'trial', 'label', 'Trial', 'type', 'number'
            )
        ),
        'rows', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'cells', jsonb_build_array(
                            to_char(m.month_start, 'YYYY-MM-DD'),
                            m.gained,
                            m.lost,
                            m.retained,
                            m.trial
                        )
                    )
                    -- Newest month first: a data table reads top-down, so the
                    -- most recent row is the one an owner wants at the top.
                    -- The chart's series stays ascending (time flows left to
                    -- right); only this table array is reversed.
                    ORDER BY m.month_start DESC
                )
                FROM metrics m
            ),
            '[]'::jsonb
        )
    )
) AS data
