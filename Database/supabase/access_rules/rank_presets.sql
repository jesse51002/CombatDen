ALTER TABLE rank_presets ENABLE ROW LEVEL SECURITY;

-- Static reference data — anyone authenticated can read so onboarding
-- flows can list available presets.
CREATE POLICY "Authenticated can view rank presets"
    ON rank_presets
    FOR SELECT
    TO authenticated
    USING (true);

-- Writes go through service_role only (this is curated reference data).
