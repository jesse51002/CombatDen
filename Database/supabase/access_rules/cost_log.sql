-- Service-role-written only: cost rows are written by the pipeline worker, never
-- by clients. Public SELECT (cost visibility); INSERT/UPDATE/DELETE revoked for
-- authenticated (tightens the old video_cost_log rule, which only revoked UPDATE).
ALTER TABLE cost_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read cost log"
    ON cost_log
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE INSERT, UPDATE, DELETE ON TABLE cost_log FROM authenticated;
