-- One-time cutover: backfill a legacy cost_log.yaml entry into the generic
-- cost_log table. No run is associated (run_id NULL) — the old global ledger
-- didn't record which run a scan belonged to; source is always 'video'.
-- created_at is set explicitly from the entry's original timestamp so the
-- backfilled history keeps its real dates instead of defaulting to now().
INSERT INTO cost_log (
    source, run_id, gym_id, stage, model, cost_usd, breakdown, note, created_at
)
VALUES (
    CAST(:source AS cost_source),
    :run_id,
    CAST(:gym_id AS UUID),
    CAST(:stage AS cost_stage),
    :model,
    :cost_usd,
    CAST(:breakdown AS JSONB),
    :note,
    :created_at
);
