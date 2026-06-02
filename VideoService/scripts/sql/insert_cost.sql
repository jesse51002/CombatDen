INSERT INTO video_cost_log (execution_type, gym_id, at, breakdown, note)
VALUES (
    CAST(:execution_type AS video_execution_type),
    :gym_id, :at, CAST(:breakdown AS jsonb), :note
)
