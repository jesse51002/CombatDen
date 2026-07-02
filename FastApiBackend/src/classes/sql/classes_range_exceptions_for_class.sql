-- Every range exception ever created for one class, newest-created first.
-- Unlike classes_range_exception_list.sql (window-scoped, reused by the
-- undo service's single-day expansion), this backs the CRM's "show me every
-- cancel range" surfaces -- no date-window filter at all.
SELECT
    exception_id,
    class_id,
    gym_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id,
    created_at
FROM class_range_exceptions
WHERE class_id = :class_id
ORDER BY created_at DESC
