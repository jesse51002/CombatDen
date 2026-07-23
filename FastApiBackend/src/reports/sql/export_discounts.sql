-- Raw discount identities for the gym (UNFILTERED base table).
SELECT
    d.discount_id,
    d.gym_id,
    d.discount_name,
    d.discount_type,
    d.is_deleted,
    d.created_at
FROM gym_discounts_unfiltered d
WHERE d.gym_id = CAST(:gym_id AS UUID)
ORDER BY d.created_at ASC, d.discount_id ASC
