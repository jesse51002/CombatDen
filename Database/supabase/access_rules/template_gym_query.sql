ALTER TABLE template_gym_query ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video gym queries"
    ON template_gym_query
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (query_id, gym_id) ON TABLE template_gym_query FROM authenticated;
