-- The whole Growth page for one gym in a single indexed scan. Ordering is
-- registry-owned (applied in Python after the unknown-key / invalid-payload
-- filter), so no ORDER BY here.
SELECT
    key,
    type,
    data,
    computed_at
FROM gym_growth_metrics
WHERE gym_id = CAST(:gym_id AS UUID)
