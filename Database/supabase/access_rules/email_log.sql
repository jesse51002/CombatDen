-- Enable Row Level Security
ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;

-- Service-role-WRITE-only: every row is claimed and updated by the backend's
-- emails domain. Clients never write here.
REVOKE INSERT, UPDATE, DELETE ON TABLE email_log FROM authenticated;

-- Policy: gym staff can read their own gym's send history — the answer to
-- "I added them and they say nothing arrived". Gym-scoped, so one gym can
-- never see another's recipients.
CREATE POLICY "Gym staff can view own gym email log"
    ON email_log
    FOR SELECT
    USING (is_gym_admin_or_owner(email_log.gym_id));
