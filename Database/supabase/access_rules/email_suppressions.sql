-- Enable Row Level Security
ALTER TABLE email_suppressions ENABLE ROW LEVEL SECURITY;

-- Service-role-only, reads included. Every row is written by the backend (an
-- unsubscribe click or a provider bounce webhook) and read only by the send
-- path.
REVOKE INSERT, UPDATE, DELETE ON TABLE email_suppressions FROM authenticated;

-- Deliberately NO select policy, unlike email_log's gym-scoped one. A global
-- suppression (gym_id IS NULL, a hard bounce) belongs to no gym, so there is no
-- correct gym predicate for it: any policy permissive enough to expose those
-- rows would expose one tenant's bounced addresses to another. With RLS enabled
-- and no policy, authenticated reads return nothing and the backend
-- (service_role, which bypasses RLS) is the only reader — which is the intended
-- surface anyway, since clients have no direct data access in this project.
