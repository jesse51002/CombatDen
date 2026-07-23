-- By Class (breakdown, count) - check-ins per class over the trailing 30
-- gym-local days, ranked by volume.
--
-- The window buckets on occurred_at (the denormalized effective start
-- instant) converted to the gym's local date. Check-ins with a NULL plan_id
-- / item_id are staff check-ins with no covering membership; they are real
-- attendance and stay counted.
--
-- A class with no check-ins in the window is absent rather than a zero row -
-- the breakdown renderer is a ranked list, not a roster. The 30-day window
-- is the metric's definition, not tunable behaviour.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
per_class AS (
    SELECT
        c.class_id,
        c.class_name,
        count(*)::bigint AS value
    FROM member_attendance a
    JOIN gym_classes c ON c.class_id = a.class_id
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (a.occurred_at AT TIME ZONE gd.tz)::date > gd.today - 30
    GROUP BY c.class_id, c.class_name
)
SELECT jsonb_build_object(
    'unit', 'count',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', CAST(pc.class_id AS TEXT),
                    'label', pc.class_name,
                    'value', pc.value
                )
                ORDER BY pc.value DESC, pc.class_name
            )
            FROM per_class pc
        ),
        '[]'::jsonb
    )
) AS data
