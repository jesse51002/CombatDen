-- Active Trials (member_list) - one row per LIVE trial membership, the ones
-- running out soonest first, so the front desk can work the list top down.
--
-- A member holding two live trial packs gets two rows: each pack has its own
-- start, its own expiry and its own conversation.
--
-- visits counts member_attendance from that pack's start_date through now,
-- bucketed on occurred_at converted to the gym's local date. Check-ins with
-- a NULL plan_id / item_id are staff check-ins with no covering membership -
-- real visits, so they stay counted.
--
-- days_left is the pack's end_date minus gym-local today. A trial with NO
-- end_date has no expiry, so its cell is a genuine null rather than an
-- invented number, and those rows sort LAST - a pack that never lapses is
-- never the most urgent call to make.
--
-- Each row carries its member_id so the CRM can deep-link straight to the
-- member; cells are positional against columns, and the date cell is an ISO
-- YYYY-MM-DD string because jsonb has no date type.
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
        mms.item_id,
        mms.start_date,
        mms.end_date
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
      AND p.plan_type = 'trial'
),
trial_rows AS (
    SELECT
        lt.member_id,
        m.first_name || ' ' || m.last_name AS member_name,
        lt.start_date,
        (
            SELECT count(*)
            FROM member_attendance a
            WHERE a.member_id = lt.member_id
              AND a.gym_id = CAST(:gym_id AS UUID)
              AND (a.occurred_at AT TIME ZONE gd.tz)::date
                  >= lt.start_date
        )::bigint AS visits,
        (lt.end_date - gd.today) AS days_left
    FROM live_trials lt
    JOIN members m ON m.member_id = lt.member_id
    CROSS JOIN gym_day gd
)
SELECT jsonb_build_object(
    'columns', jsonb_build_array(
        jsonb_build_object(
            'key', 'name', 'label', 'Member', 'type', 'text'
        ),
        jsonb_build_object(
            'key', 'started', 'label', 'Started', 'type', 'date'
        ),
        jsonb_build_object(
            'key', 'visits',
            'label', 'Visits',
            'type', 'number',
            'align', 'right'
        ),
        jsonb_build_object(
            'key', 'days_left',
            'label', 'Days Left',
            'type', 'number',
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
                        to_char(r.start_date, 'YYYY-MM-DD'),
                        r.visits,
                        r.days_left
                    )
                )
                ORDER BY r.days_left ASC NULLS LAST,
                         r.member_name ASC
            )
            FROM trial_rows r
        ),
        '[]'::jsonb
    )
) AS data
