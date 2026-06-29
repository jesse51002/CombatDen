-- Every range exception overlapping the materialize window, across all gyms.
-- Grouped by class_id in Python and fed to the canonical expander. Column set
-- matches to_expander_range() plus class_id for the grouping. Overlap test
-- mirrors the schedule reader's range-exception load exactly.
SELECT
    class_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id,
    created_at
FROM class_range_exceptions
WHERE start_date <= :window_end
  AND end_date >= :window_start
