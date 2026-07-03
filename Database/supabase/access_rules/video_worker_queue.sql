-- Enable Row Level Security
ALTER TABLE video_worker_queue ENABLE ROW LEVEL SECURITY;

-- No RLS policies: service-level-only queue infrastructure (the backend
-- enqueues, the VideoService worker pops; the CRM's status endpoint reads it
-- through the backend). No client access, like resource_locks.
REVOKE ALL ON TABLE video_worker_queue FROM authenticated;
