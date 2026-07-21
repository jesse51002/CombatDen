-- At-Risk Members (member_list) - members with a live membership who have not
-- checked in for at least the at-risk window (or have never checked in at
-- all), ranked by how much monthly recurring revenue is at stake.
--
-- Money is member_memberships.total_price, the POST-discount price the payment
-- sync writes back; discount math is never re-derived here. Each row carries
-- its member_id so the CRM can deep-link straight to the member.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
active_members AS (
    SELECT
        mms.member_id,
        COALESCE(
            sum(mms.total_price) FILTER (WHERE p.plan_type = 'recurring'),
            0
        )::bigint AS monthly_cents
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
    GROUP BY mms.member_id
),
at_risk AS (
    SELECT
        m.member_id,
        m.first_name || ' ' || m.last_name AS member_name,
        (m.last_class AT TIME ZONE gd.tz)::date AS last_class_date,
        am.monthly_cents
    FROM members m
    JOIN active_members am ON am.member_id = m.member_id
    CROSS JOIN gym_day gd
    WHERE m.gym_id = CAST(:gym_id AS UUID)
      AND (
          m.last_class IS NULL
          OR (m.last_class AT TIME ZONE gd.tz)::date
             <= gd.today - CAST(:at_risk_days AS INTEGER)
      )
)
SELECT jsonb_build_object(
    'columns', jsonb_build_array(
        jsonb_build_object(
            'key', 'name', 'label', 'Member', 'type', 'text'
        ),
        jsonb_build_object(
            'key', 'last_class', 'label', 'Last Check-in', 'type', 'date'
        ),
        jsonb_build_object(
            'key', 'monthly',
            'label', 'Monthly',
            'type', 'cents',
            'align', 'right'
        )
    ),
    'rows', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'member_id', CAST(r.member_id AS TEXT),
                    'cells', jsonb_build_array(
                        r.member_name,
                        to_char(r.last_class_date, 'YYYY-MM-DD'),
                        r.monthly_cents
                    )
                )
                ORDER BY r.monthly_cents DESC,
                         r.last_class_date ASC NULLS FIRST
            )
            FROM at_risk r
        ),
        '[]'::jsonb
    )
) AS data
