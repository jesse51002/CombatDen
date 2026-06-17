-- Backend-executed tracked operations. A task is created by the backend when a
-- gym-staff request kicks off work that runs in the background (the request
-- returns the task_id immediately; the CRM polls). One task = one operation
-- request; its per-membership work units live in task_items (one row each), so
-- progress, completions, and failures are visible per item. Generic by design:
-- task_type discriminates the operation (membership_reprice today; payer
-- changes / bulk ops later) and the items table carries the op parameters.
--
-- Tasks and their items are records — written by the backend (service_role)
-- only, readable by gym staff, never updated or deleted by clients.

-- What operation the task performs. Each value has a registered executor in
-- the backend (src/tasks/service/tasks_executor.py).
CREATE TYPE task_type AS ENUM (
    'membership_reprice'
);

-- Lifecycle of a task and of each of its items. Items: 'pending' = queued
-- (also the state a retryable failure returns to), 'running' = claimed by an
-- executor, then 'completed' or 'failed' (terminal, after max attempts).
-- Tasks: 'pending' until the first item is claimed, 'running' while items are
-- in flight, then 'completed' (all items completed) or 'failed' (any item
-- failed).
CREATE TYPE task_status AS ENUM (
    'pending',
    'running',
    'completed',
    'failed'
);

CREATE TABLE tasks (
    task_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_task_gym REFERENCES gyms(gym_id),
    task_type task_type NOT NULL,
    status task_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    PRIMARY KEY (task_id),
    -- Composite-FK anchor so task_items can pin (task_id, gym_id) together.
    UNIQUE (task_id, gym_id)
);

-- The CRM's ongoing-tasks poll filters by gym + status.
CREATE INDEX idx_tasks_gym_status ON tasks (gym_id, status);

-- The crash-recovery sweep scans for unfinished tasks across all gyms.
CREATE INDEX idx_tasks_unfinished ON tasks (status)
    WHERE status IN ('pending', 'running');
