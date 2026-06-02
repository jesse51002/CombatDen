ALTER TABLE video ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read videos"
    ON video
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (video_id) ON TABLE video FROM authenticated;
