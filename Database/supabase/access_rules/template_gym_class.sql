ALTER TABLE template_gym_class ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video gym classes"
    ON template_gym_class
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (class_id, gym_id) ON TABLE template_gym_class FROM authenticated;
