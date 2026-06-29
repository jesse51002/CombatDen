-- Every instance exception whose original_date falls in the materialize window,
-- across all gyms. Grouped by class_id in Python and fed to the canonical
-- expander (which indexes instance exceptions by original_date). Column set
-- matches to_expander_instance() plus class_id for the grouping. Window-by-
-- original_date mirrors the schedule reader's exception load exactly.
SELECT
    class_id,
    original_date,
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_instructor_id,
    new_date,
    created_at
FROM class_instance_exceptions
WHERE original_date >= :window_start
  AND original_date <= :window_end
