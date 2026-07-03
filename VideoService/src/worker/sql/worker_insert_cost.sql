-- Append one per-stage spend row for this run to the ledger. entry_id defaults.
-- breakdown is a USD component map (e.g. {"apify_usd": 0.18} / {"llm_usd": ...}).
INSERT INTO video_cost_log (
    execution_type, gym_id, video_run_id, at, breakdown, note
)
VALUES (
    CAST(:execution_type AS video_execution_type),
    CAST(:gym_id AS UUID),
    CAST(:run_id AS UUID),
    :at,
    CAST(:breakdown AS JSONB),
    :note
);
