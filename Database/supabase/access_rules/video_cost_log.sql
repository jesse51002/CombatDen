-- Append-only: REVOKE UPDATE entirely for authenticated (logs/history pattern).
ALTER TABLE video_cost_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video cost log"
    ON video_cost_log
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE ON TABLE video_cost_log FROM authenticated;
