-- One row per (gym, metric key). A recompute overwrites the payload in place,
-- so a metric that fails this tick keeps its previous (stale but valid) row
-- rather than disappearing from the page.
INSERT INTO gym_growth_metrics (gym_id, key, type, data, computed_at)
VALUES (
    CAST(:gym_id AS UUID),
    :key,
    :type,
    CAST(:data AS JSONB),
    now()
)
ON CONFLICT (gym_id, key) DO UPDATE
SET type = EXCLUDED.type,
    data = EXCLUDED.data,
    computed_at = EXCLUDED.computed_at
