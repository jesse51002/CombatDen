-- Member Tenure (breakdown, count) - how long the gym's members have been
-- members, bucketed by whole months since their FIRST membership start_date.
--
-- Tenure is measured from the first membership, not from members.created_at: a
-- member row can exist for weeks (a lead, an unfinished sign-up) before anyone
-- pays for anything, and counting that as tenure would inflate every bucket.
-- The consequence is deliberate - a member who has NEVER held a membership is
-- EXCLUDED here entirely, even though they still count in the total-members
-- KPI tile, which counts member rows.
--
-- The month count is age()-derived, never a day count divided by 30, so
-- month-length and leap years cannot drift the boundaries. All four buckets
-- are always emitted, zeros included, so the breakdown keeps a stable shape.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
first_membership AS (
    SELECT
        mm.member_id,
        min(mm.start_date) AS first_start
    FROM member_memberships mm
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
    GROUP BY mm.member_id
),
tenure AS (
    SELECT
        (
            date_part('year', age(gd.today, f.first_start)) * 12
            + date_part('month', age(gd.today, f.first_start))
        )::int AS months
    FROM first_membership f
    CROSS JOIN gym_day gd
),
counts AS (
    SELECT
        count(*) FILTER (WHERE t.months < 3)::bigint AS under_3,
        count(*) FILTER (
            WHERE t.months >= 3 AND t.months < 6
        )::bigint AS m3_6,
        count(*) FILTER (
            WHERE t.months >= 6 AND t.months < 12
        )::bigint AS m6_12,
        count(*) FILTER (WHERE t.months >= 12)::bigint AS m12_plus
    FROM tenure t
)
SELECT jsonb_build_object(
    'unit', 'count',
    'items', jsonb_build_array(
        jsonb_build_object(
            'key', 'under_3',
            'label', 'Under 3 months',
            'value', c.under_3
        ),
        jsonb_build_object(
            'key', '3_6',
            'label', '3-6 months',
            'value', c.m3_6
        ),
        jsonb_build_object(
            'key', '6_12',
            'label', '6-12 months',
            'value', c.m6_12
        ),
        jsonb_build_object(
            'key', '12_plus',
            'label', '12+ months',
            'value', c.m12_plus
        )
    )
) AS data
FROM counts c
