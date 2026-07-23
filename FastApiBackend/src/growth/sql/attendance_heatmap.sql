-- Busy Times (heatmap, count) - check-ins over the trailing 90 gym-local days,
-- bucketed by weekday and hour of day IN THE GYM'S TIMEZONE (occurred_at is
-- the denormalized effective start instant, so it is the right bucket key).
--
-- rows are always the seven weekdays; cols cover only the hours the gym
-- actually has activity in (falling back to a sane daytime span when there is
-- no attendance at all), so a 24-column grid of mostly zeros is never sent.
-- by_class repeats the same grid per class that appears in the window.
--
-- The 90-day window is the metric's definition, not tunable behaviour.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
att AS (
    SELECT
        a.class_id,
        c.class_name,
        EXTRACT(ISODOW FROM (a.occurred_at AT TIME ZONE gd.tz))::int AS dow,
        EXTRACT(HOUR FROM (a.occurred_at AT TIME ZONE gd.tz))::int AS hr
    FROM member_attendance a
    JOIN gym_classes c ON c.class_id = a.class_id
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (a.occurred_at AT TIME ZONE gd.tz)::date > gd.today - 90
),
hour_span AS (
    SELECT
        COALESCE(min(a.hr), 6) AS min_hr,
        COALESCE(max(a.hr), 21) AS max_hr
    FROM att a
),
cols AS (
    SELECT gs.hr
    FROM hour_span h
    CROSS JOIN generate_series(h.min_hr, h.max_hr) AS gs(hr)
),
grid AS (
    SELECT d.dow, c.hr
    FROM generate_series(1, 7) AS d(dow)
    CROSS JOIN cols c
),
cells AS (
    SELECT
        g.dow,
        g.hr,
        count(a.dow)::bigint AS value
    FROM grid g
    LEFT JOIN att a ON a.dow = g.dow AND a.hr = g.hr
    GROUP BY g.dow, g.hr
),
grid_rows AS (
    SELECT c.dow, jsonb_agg(c.value ORDER BY c.hr) AS row_cells
    FROM cells c
    GROUP BY c.dow
),
class_cells AS (
    SELECT
        cl.class_id,
        cl.class_name,
        g.dow,
        g.hr,
        count(a.dow)::bigint AS value
    FROM (SELECT DISTINCT class_id, class_name FROM att) cl
    CROSS JOIN grid g
    LEFT JOIN att a
        ON a.class_id = cl.class_id
       AND a.dow = g.dow
       AND a.hr = g.hr
    GROUP BY cl.class_id, cl.class_name, g.dow, g.hr
),
class_rows AS (
    SELECT
        cc.class_id,
        cc.class_name,
        cc.dow,
        jsonb_agg(cc.value ORDER BY cc.hr) AS row_cells
    FROM class_cells cc
    GROUP BY cc.class_id, cc.class_name, cc.dow
),
class_grids AS (
    SELECT
        cr.class_id,
        cr.class_name,
        jsonb_agg(cr.row_cells ORDER BY cr.dow) AS cells
    FROM class_rows cr
    GROUP BY cr.class_id, cr.class_name
)
SELECT jsonb_build_object(
    'unit', 'count',
    'rows', jsonb_build_array(
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ),
    'cols', COALESCE(
        (
            SELECT jsonb_agg(
                to_char(make_time(c.hr, 0, 0), 'FMHH12AM') ORDER BY c.hr
            )
            FROM cols c
        ),
        '[]'::jsonb
    ),
    'cells', COALESCE(
        (
            SELECT jsonb_agg(r.row_cells ORDER BY r.dow)
            FROM grid_rows r
        ),
        '[]'::jsonb
    ),
    'by_class', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'class_id', CAST(cg.class_id AS TEXT),
                    'class_name', cg.class_name,
                    'cells', cg.cells
                )
                ORDER BY cg.class_name
            )
            FROM class_grids cg
        ),
        '[]'::jsonb
    )
) AS data
