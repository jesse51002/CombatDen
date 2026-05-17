-- members augmented with current account status (trial / full / disabled
-- / inactive), engagement (`active` boolean), and last_class_days_ago.
--
-- `status` is computed from member_status: a member is "inactive" if no
-- member_status row currently covers today.
--
-- `active` is computed from member_active: true iff a member_active row
-- with active_type='active' currently covers today; false otherwise
-- (including when there's no covering row at all).
--
-- The gist EXCLUDE on each underlying table guarantees at most one
-- current period per member, so each subquery returns exactly 0 or 1
-- row.
--
-- security_invoker so RLS on the underlying tables propagates through
-- the view; otherwise it would silently bypass tenant isolation.
CREATE OR REPLACE VIEW members_with_status
WITH (security_invoker = true) AS
SELECT
    m.*,
    COALESCE(
        (SELECT s.status_type::TEXT
         FROM member_status s
         WHERE s.member_id = m.member_id
           AND s.start_date <= CURRENT_DATE
           AND (s.end_date IS NULL OR s.end_date >= CURRENT_DATE)
         LIMIT 1),
        'inactive'
    ) AS status,
    COALESCE(
        (SELECT a.active_type = 'active'
         FROM member_active a
         WHERE a.member_id = m.member_id
           AND a.start_date <= CURRENT_DATE
           AND (a.end_date IS NULL OR a.end_date >= CURRENT_DATE)
         LIMIT 1),
        FALSE
    ) AS active,
    CASE
        WHEN m.last_class IS NULL THEN NULL
        ELSE (CURRENT_DATE - m.last_class::DATE)
    END AS last_class_days_ago
FROM members m;
