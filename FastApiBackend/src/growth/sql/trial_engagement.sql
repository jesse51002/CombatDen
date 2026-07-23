-- Trial Engagement (breakdown, count) - the members on a LIVE trial right
-- now, bucketed by how many times they have actually shown up during it.
--
-- This is the "is this trial working" metric: a full bucket at 0 visits is a
-- pile of paid-for trials that never walked through the door.
--
-- A member is counted ONCE even if they hold two live trial packs; their
-- window starts at the EARLIEST live trial start so nothing they did on the
-- pack they are still on is dropped. Visits are member_attendance rows from
-- that start through today, bucketed on occurred_at converted to the gym's
-- local date. Check-ins with a NULL plan_id / item_id are staff check-ins
-- with no covering membership - they are real visits and stay counted.
--
-- All four buckets are always emitted, at 0 when empty, so the breakdown
-- does not change shape as the trial roster moves.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
live_trials AS (
    SELECT
        mms.member_id,
        min(mms.start_date) AS trial_start
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
      AND p.plan_type = 'trial'
      AND mms.start_date IS NOT NULL
    GROUP BY mms.member_id
),
visits AS (
    SELECT
        lt.member_id,
        (
            SELECT count(*)
            FROM member_attendance a
            WHERE a.member_id = lt.member_id
              AND a.gym_id = CAST(:gym_id AS UUID)
              AND (a.occurred_at AT TIME ZONE gd.tz)::date
                  >= lt.trial_start
        )::bigint AS visit_count
    FROM live_trials lt
    CROSS JOIN gym_day gd
),
buckets AS (
    SELECT
        b.bucket_key,
        b.bucket_label,
        b.sort_order,
        count(v.member_id)::bigint AS value
    FROM (VALUES
        ('none', 'No visits', 1, 0, 0),
        ('low', '1-2 visits', 2, 1, 2),
        ('mid', '3-5 visits', 3, 3, 5),
        ('high', '6+ visits', 4, 6, NULL)
    ) AS b(bucket_key, bucket_label, sort_order, lo, hi)
    LEFT JOIN visits v
        ON v.visit_count >= b.lo
       AND (b.hi IS NULL OR v.visit_count <= b.hi)
    GROUP BY b.bucket_key, b.bucket_label, b.sort_order
)
SELECT jsonb_build_object(
    'unit', 'count',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', bk.bucket_key,
                    'label', bk.bucket_label,
                    'value', bk.value
                )
                ORDER BY bk.sort_order
            )
            FROM buckets bk
        ),
        '[]'::jsonb
    )
) AS data
