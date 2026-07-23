-- Hand-authored migration.
-- Two paired changes for the Growth page going live.
--
-- 1) CREATE gym_growth_metrics (schemas/gym_growth_metrics.sql +
--    access_rules/gym_growth_metrics.sql) — the generic per-gym metric cache.
--    The backend's growth domain recomputes every metric at launch and hourly
--    and UPSERTs one row per (gym_id, key). Only the payload is stored:
--    display metadata (name, categories, order) is registry-owned in the
--    backend and attached at serve time, so a rename or reorder needs no
--    recompute and no migration. `data` is validated on READ against the
--    registry's model for that key; an unknown key or a mismatched payload is
--    skipped and self-heals at the next compute. Service-role-WRITE-only with
--    a gym-staff SELECT policy — clients never write metrics.
--
-- 2) DROP TABLE gym_history — the daily active/inactive snapshot rollup. It is
--    replaced, not merely retired: the growth domain derives all history fresh
--    from the source tables (member_memberships, member_attendance) on every
--    hourly compute, so a separately-maintained snapshot table is now a second
--    source of truth that can only drift. Its seed writers
--    (python_data/generators/history.py, bootstrap/history.py,
--    schema/gym_history.py) and its access-rule file are removed in the same
--    change, so `make seed` stays green.
--
-- Order matters: the DROP comes last so a failure creating the new table
-- leaves the old one in place. No data migration between them — gym_history
-- held only derived counts, all of which the growth compute recalculates from
-- the underlying rows.

CREATE TABLE gym_growth_metrics (
    metric_id UUID NOT NULL DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL CONSTRAINT fk_growth_metrics_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    type TEXT NOT NULL,
    data JSONB NOT NULL CONSTRAINT growth_metrics_data_is_object CHECK (jsonb_typeof(data) = 'object'),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (metric_id),
    CONSTRAINT uq_growth_metrics_gym_key UNIQUE (gym_id, key)
);

CREATE INDEX idx_gym_growth_metrics_gym_id ON gym_growth_metrics (gym_id);

-- Access rules (mirrors access_rules/gym_growth_metrics.sql).
ALTER TABLE gym_growth_metrics ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON TABLE gym_growth_metrics FROM authenticated;

CREATE POLICY "Gym staff can view own gym growth metrics"
    ON gym_growth_metrics
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_growth_metrics.gym_id));

-- The snapshot table the growth domain replaces. Its only policy is dropped
-- with the table; nothing else references it (no FKs point at gym_history).
DROP TABLE IF EXISTS gym_history;
