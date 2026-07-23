-- Cohort Retention (heatmap, percent).
--
-- rows are the last 6 monthly cohorts - members grouped by the month of their
-- FIRST membership start, labelled YYYY-MM. cols are the three ages 30d / 60d
-- / 90d. A cell is the share of that cohort who had still not crossed into
-- dormancy by that age, measured per member from their OWN first_start (not
-- from the month boundary), so a member who joined on the 28th gets the same
-- 30 days as one who joined on the 1st.
--
-- THE IMMATURITY RULE (this is why the cell type is nullable). A cohort has
-- matured to an age only when EVERY member in it has had that many days to
-- churn - the cohort month's LAST day plus the age must be on or before
-- gym-local today. A cohort younger than that has not been measured yet, so
-- its cell is JSON null, never 0: a 0 would render as total churn and read as
-- a catastrophe when the real answer is "ask again next month". The newest
-- cohorts therefore fill in from left to right as they age.
WITH
{dormant_cte},
bounds AS (
    SELECT gd.today FROM gym_day gd
),
cohorts AS (
    SELECT
        date_trunc('month', d.first_start::timestamp)::date AS cohort_start,
        (
            date_trunc('month', d.first_start::timestamp)
            + INTERVAL '1 month' - INTERVAL '1 day'
        )::date AS cohort_end,
        count(*)::numeric AS cohort_size,
        count(*) FILTER (
            WHERE NOT d.dormant OR d.dormant_since > d.first_start + 30
        )::numeric AS held_30,
        count(*) FILTER (
            WHERE NOT d.dormant OR d.dormant_since > d.first_start + 60
        )::numeric AS held_60,
        count(*) FILTER (
            WHERE NOT d.dormant OR d.dormant_since > d.first_start + 90
        )::numeric AS held_90
    FROM member_dormancy d
    WHERE d.first_start IS NOT NULL
    GROUP BY 1, 2
),
recent AS (
    SELECT
        c.cohort_start,
        c.cohort_size,
        c.held_30,
        c.held_60,
        c.held_90,
        (c.cohort_end + 30 <= b.today) AS mature_30,
        (c.cohort_end + 60 <= b.today) AS mature_60,
        (c.cohort_end + 90 <= b.today) AS mature_90
    FROM cohorts c
    CROSS JOIN bounds b
    ORDER BY c.cohort_start DESC
    LIMIT 6
)
SELECT jsonb_build_object(
    'unit', 'percent',
    'rows', COALESCE(
        (
            SELECT jsonb_agg(
                to_char(r.cohort_start, 'YYYY-MM') ORDER BY r.cohort_start
            )
            FROM recent r
        ),
        '[]'::jsonb
    ),
    'cols', jsonb_build_array('30d', '60d', '90d'),
    'cells', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_array(
                    CASE
                        WHEN r.mature_30 THEN COALESCE(
                            round(
                                r.held_30 / NULLIF(r.cohort_size, 0) * 100, 1
                            ), 0)
                    END,
                    CASE
                        WHEN r.mature_60 THEN COALESCE(
                            round(
                                r.held_60 / NULLIF(r.cohort_size, 0) * 100, 1
                            ), 0)
                    END,
                    CASE
                        WHEN r.mature_90 THEN COALESCE(
                            round(
                                r.held_90 / NULLIF(r.cohort_size, 0) * 100, 1
                            ), 0)
                    END
                )
                ORDER BY r.cohort_start
            )
            FROM recent r
        ),
        '[]'::jsonb
    )
) AS data
