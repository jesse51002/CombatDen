-- Status Mix (breakdown, count) - where every member of the gym stands right
-- now, each member counted EXACTLY ONCE.
--
-- A member can satisfy several of these rules at the same time (an overdue
-- trial that is also frozen), so the mix only adds up if one status wins. The
-- PRECEDENCE, highest first:
--   1. dormant  - the canonical dormancy rule from the shared CTE (every
--                 membership terminal, or only trial / one_time packs left and
--                 no activity inside the window). A lost member is never also
--                 reported as active.
--   2. overdue  - an active membership whose due date has already passed. The
--                 shared predicate (src/shared/sql/membership_overdue.sql,
--                 injected as the is_overdue template variable), so this
--                 bucket, the money tiles, the members-list Overdue tab and
--                 the check-in gate are ONE text and cannot disagree about
--                 who is late.
--   3. frozen   - a frozen membership (member_memberships_status derives the
--                 freeze from the SUBJECT member's freeze window).
--   4. trial    - an active membership on a trial plan.
--   5. active   - any other active membership.
--
-- A member with NO membership rows at all lands in no bucket: unenrolled is
-- not a status, and the dormancy rule deliberately never brands them lost.
-- The five buckets are always emitted, zeros included, so the breakdown keeps
-- a stable shape on a quiet gym.
WITH
{dormant_cte},
member_flags AS (
    SELECT
        mms.member_id,
        bool_or(mms.status = 'active') AS has_active,
        bool_or(mms.status = 'frozen') AS has_frozen,
        bool_or(
            mms.status = 'active' AND p.plan_type = 'trial'
        ) AS has_trial,
        bool_or({is_overdue}) AS has_overdue
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    CROSS JOIN gym_day gd
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
    GROUP BY mms.member_id
),
classified AS (
    SELECT
        CASE
            -- The status mix LABELS this bucket "Dormant", so it uses the
            -- members-list meaning (only-live-short-packs + gone quiet), NOT
            -- the broader case-(a)+(b) churn flag. An all-terminal member is
            -- churned (counted by the lost/churn metrics) but reads as
            -- cancelled, not dormant -- so they land in no live-status bucket
            -- here, exactly as the members list shows them.
            WHEN d.dormant_unused_pack THEN 'dormant'
            WHEN f.has_overdue THEN 'overdue'
            WHEN f.has_frozen THEN 'frozen'
            WHEN f.has_trial THEN 'trial'
            WHEN f.has_active THEN 'active'
        END AS bucket
    FROM member_dormancy d
    LEFT JOIN member_flags f ON f.member_id = d.member_id
),
counts AS (
    SELECT
        count(*) FILTER (WHERE c.bucket = 'active')::bigint AS active,
        count(*) FILTER (WHERE c.bucket = 'trial')::bigint AS trial,
        count(*) FILTER (WHERE c.bucket = 'frozen')::bigint AS frozen,
        count(*) FILTER (WHERE c.bucket = 'overdue')::bigint AS overdue,
        count(*) FILTER (WHERE c.bucket = 'dormant')::bigint AS dormant
    FROM classified c
)
SELECT jsonb_build_object(
    'unit', 'count',
    'items', jsonb_build_array(
        jsonb_build_object(
            'key', 'active',
            'label', 'Active',
            'value', c.active
        ),
        jsonb_build_object(
            'key', 'trial',
            'label', 'Trial',
            'value', c.trial
        ),
        jsonb_build_object(
            'key', 'frozen',
            'label', 'Frozen',
            'value', c.frozen
        ),
        jsonb_build_object(
            'key', 'overdue',
            'label', 'Overdue',
            'value', c.overdue
        ),
        jsonb_build_object(
            'key', 'dormant',
            'label', 'Dormant',
            'value', c.dormant
        )
    )
) AS data
FROM counts c
