-- The class's capacity inputs needed to resolve a sign-up's effective
-- max_capacity: the class's own max_capacity plus any per-occurrence override
-- from class_instance_exceptions for (class_id, occurrence_date). The caller
-- resolves the effective value (exception_max_capacity wins when set); NULL
-- means unlimited -- never blocks. gym_id scopes the class to the requesting
-- gym; no row means the class doesn't belong to this gym (or doesn't exist).
SELECT
    c.class_id,
    c.gym_id,
    c.max_capacity,
    ie.new_max_capacity AS exception_max_capacity
FROM gym_classes c
LEFT JOIN class_instance_exceptions ie
    ON ie.class_id = c.class_id
    AND ie.original_date = CAST(:occurrence_date AS DATE)
WHERE c.class_id = CAST(:class_id AS UUID)
  AND c.gym_id = CAST(:gym_id AS UUID)
