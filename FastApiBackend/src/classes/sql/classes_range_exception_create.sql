-- Create a continuous-range override (cancel and/or substitute instructor).
INSERT INTO class_range_exceptions (
    class_id,
    gym_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id
)
VALUES (
    :class_id,
    :gym_id,
    :start_date,
    :end_date,
    :is_cancelled,
    :new_instructor_id
)
RETURNING
    exception_id,
    class_id,
    gym_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id,
    created_at
