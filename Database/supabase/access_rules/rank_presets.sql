ALTER TABLE rank_presets ENABLE ROW LEVEL SECURITY;

-- Static reference data — anyone authenticated can read so onboarding
-- flows can list available presets.
CREATE POLICY "Authenticated can view rank presets"
    ON rank_presets
    FOR SELECT
    TO authenticated
    USING (true);

-- Writes go through service_role only (this is curated reference data).

-- Explicit role grants (normally supplied by Supabase's platform default
-- privileges, but declared here because the two-level migration DROP+CREATEs
-- this table and a recreated table does not re-inherit those defaults — see
-- migrations/20260706000000_ranks_two_level_model.sql). RLS governs actual
-- row access; service_role bypasses RLS for the curated-data seed/writes.
GRANT ALL ON TABLE rank_presets TO anon;
GRANT ALL ON TABLE rank_presets TO authenticated;
GRANT ALL ON TABLE rank_presets TO service_role;
