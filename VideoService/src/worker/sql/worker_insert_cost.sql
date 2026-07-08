-- Append one per-stage spend row for this run to the generic ledger. entry_id
-- and created_at default. breakdown is a USD component map (e.g.
-- {"apify_usd": 0.18} / {"llm_usd": ...}); cost_usd is the row's single total.
INSERT INTO cost_log (
    source, run_id, gym_id, stage, model, cost_usd, breakdown, note
)
VALUES (
    CAST(:source AS cost_source),
    :run_id,
    CAST(:gym_id AS UUID),
    CAST(:stage AS cost_stage),
    :model,
    :cost_usd,
    CAST(:breakdown AS JSONB),
    :note
);
