-- Enable Row Level Security
ALTER TABLE stripe_webhook_events ENABLE ROW LEVEL SECURITY;

-- No RLS policies: only service role accesses this table
REVOKE ALL ON TABLE stripe_webhook_events FROM authenticated;
