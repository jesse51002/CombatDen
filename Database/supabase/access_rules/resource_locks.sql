-- Enable Row Level Security
ALTER TABLE resource_locks ENABLE ROW LEVEL SECURITY;

-- No RLS policies: service-role-only infrastructure lock table (no client access).
REVOKE ALL ON TABLE resource_locks FROM authenticated;
