-- Members (kpi_group, count) - four headline tiles for the current gym-local
-- month, each compared against the previous month where a comparison is
-- meaningful.
--
--   total - every member row the gym has (previous = rows created before this
--           month started)
--   new   - members whose FIRST membership started this month
--   lost  - members who became dormant this month (canonical dormancy rule)
--   trial - members whose current live membership is on a trial plan; there is
--           no honest previous-month equivalent (the view is point-in-time),
--           so its delta is deliberately null
WITH
{dormant_cte},
bounds AS (
    SELECT
        gd.tz,
        gd.today,
        date_trunc('month', gd.today)::date AS month_start,
        (date_trunc('month', gd.today) + INTERVAL '1 month')::date
            AS next_month_start,
        (date_trunc('month', gd.today) - INTERVAL '1 month')::date
            AS prev_month_start
    FROM gym_day gd
),
totals AS (
    SELECT
        count(*)::bigint AS total_now,
        count(*) FILTER (
            WHERE (m.created_at AT TIME ZONE b.tz)::date < b.month_start
        )::bigint AS total_prev
    FROM members m
    CROSS JOIN bounds b
    WHERE m.gym_id = CAST(:gym_id AS UUID)
),
gained AS (
    SELECT
        count(*) FILTER (
            WHERE d.first_start >= b.month_start
              AND d.first_start < b.next_month_start
        )::bigint AS new_now,
        count(*) FILTER (
            WHERE d.first_start >= b.prev_month_start
              AND d.first_start < b.month_start
        )::bigint AS new_prev
    FROM member_dormancy d
    CROSS JOIN bounds b
),
lost AS (
    SELECT
        count(*) FILTER (
            WHERE d.dormant
              AND d.dormant_since >= b.month_start
              AND d.dormant_since < b.next_month_start
        )::bigint AS lost_now,
        count(*) FILTER (
            WHERE d.dormant
              AND d.dormant_since >= b.prev_month_start
              AND d.dormant_since < b.month_start
        )::bigint AS lost_prev
    FROM member_dormancy d
    CROSS JOIN bounds b
),
trials AS (
    SELECT count(DISTINCT mms.member_id)::bigint AS trial_now
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
      AND p.plan_type = 'trial'
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'total',
            'label', 'Total Members',
            'value', t.total_now,
            'unit', 'count',
            'delta_abs', t.total_now - t.total_prev,
            'delta_pct', CASE
                WHEN t.total_prev > 0
                    THEN round(
                        (t.total_now - t.total_prev)::numeric
                        / t.total_prev * 100, 1)
            END,
            'compare_label', 'vs last month'
        ),
        jsonb_build_object(
            'key', 'new',
            'label', 'New This Month',
            'value', g.new_now,
            'unit', 'count',
            'delta_abs', g.new_now - g.new_prev,
            'delta_pct', CASE
                WHEN g.new_prev > 0
                    THEN round(
                        (g.new_now - g.new_prev)::numeric
                        / g.new_prev * 100, 1)
            END,
            'compare_label', 'vs last month'
        ),
        jsonb_build_object(
            'key', 'lost',
            'label', 'Lost This Month',
            'value', l.lost_now,
            'unit', 'count',
            'delta_abs', l.lost_now - l.lost_prev,
            'delta_pct', CASE
                WHEN l.lost_prev > 0
                    THEN round(
                        (l.lost_now - l.lost_prev)::numeric
                        / l.lost_prev * 100, 1)
            END,
            'compare_label', 'vs last month'
        ),
        jsonb_build_object(
            'key', 'trial',
            'label', 'On Trial',
            'value', tr.trial_now,
            'unit', 'count'
        )
    )
) AS data
FROM totals t
CROSS JOIN gained g
CROSS JOIN lost l
CROSS JOIN trials tr
