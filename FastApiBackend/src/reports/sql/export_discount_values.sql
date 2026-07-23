-- Raw versioned discount values for the gym (UNFILTERED base table).
SELECT
    v.value_id,
    v.discount_id,
    v.gym_id,
    v.percentage_off,
    v.dollar_off,
    v.duration_amount,
    v.duration_unit,
    v.end_date,
    v.is_active,
    v.created_at
FROM gym_discount_values_unfiltered v
WHERE v.gym_id = CAST(:gym_id AS UUID)
ORDER BY v.created_at ASC, v.value_id ASC
