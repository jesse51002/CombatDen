-- Class Fill Rate (breakdown, percent) - how full a class runs, over the
-- trailing 30 gym-local days.
--
-- Class OCCURRENCES are never stored: they are computed at read time from
-- the versioned gym_class_schedules by a Python expander, so there is no
-- table of "scheduled slots" to count and no attempt is made to rebuild one
-- here. An occurrence is therefore taken to be a DISTINCT
-- (original_date, original_time) slot that actually has attendance in the
-- window, and the fill rate is
--
--     average attendance per attended occurrence / max_capacity
--
-- A class whose max_capacity is NULL is UNLIMITED, which has no fill rate at
-- all (every denominator would be infinite), so those classes are excluded
-- rather than reported as 0% or 100%.
--
-- The value can exceed 100 when staff checked more people in than the cap
-- allows; that is real and is not clamped. The 30-day window is the metric's
-- definition, not tunable behaviour.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
occurrences AS (
    SELECT
        a.class_id,
        a.original_date,
        a.original_time,
        count(*)::bigint AS attended
    FROM member_attendance a
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (a.occurred_at AT TIME ZONE gd.tz)::date > gd.today - 30
    GROUP BY a.class_id, a.original_date, a.original_time
),
per_class AS (
    SELECT
        c.class_id,
        c.class_name,
        c.max_capacity,
        avg(o.attended) AS avg_attended
    FROM occurrences o
    JOIN gym_classes c ON c.class_id = o.class_id
    WHERE c.max_capacity IS NOT NULL
    GROUP BY c.class_id, c.class_name, c.max_capacity
),
rates AS (
    SELECT
        pc.class_id,
        pc.class_name,
        COALESCE(
            round(
                pc.avg_attended / NULLIF(pc.max_capacity, 0) * 100, 1
            ),
            0
        ) AS fill_pct
    FROM per_class pc
)
SELECT jsonb_build_object(
    'unit', 'percent',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', CAST(r.class_id AS TEXT),
                    'label', r.class_name,
                    'value', r.fill_pct
                )
                ORDER BY r.fill_pct DESC, r.class_name
            )
            FROM rates r
        ),
        '[]'::jsonb
    )
) AS data
