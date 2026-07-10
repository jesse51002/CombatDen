-- VideoService demo content is public, read-only. No write policies => writes are
-- denied to anon/authenticated by default; the scraper/scan/sync write via the
-- service-role connection (RLS-exempt).
ALTER TABLE template_gym ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video gyms"
    ON template_gym
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (gym_id) ON TABLE template_gym FROM authenticated;
