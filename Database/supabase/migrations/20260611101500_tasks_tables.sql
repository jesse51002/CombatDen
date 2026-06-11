-- Backend-executed tracked operations: tasks + per-membership task_items.
-- A task is created when a gym-staff request kicks off background work (the
-- request returns the task_id; the CRM polls); each item tracks one
-- membership-level operation (status, attempts, error, old→new row linkage).
-- membership_reprice is the first task_type. Mirrors schemas/tasks.sql and
-- schemas/task_items.sql.

CREATE TYPE task_type AS ENUM (
    'membership_reprice'
);

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
    UNIQUE (task_id, gym_id)
);

CREATE INDEX idx_tasks_gym_status ON tasks (gym_id, status);
CREATE INDEX idx_tasks_unfinished ON tasks (status)
    WHERE status IN ('pending', 'running');

CREATE TABLE task_items (
    task_item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL CONSTRAINT fk_task_item_task REFERENCES tasks(task_id),
    gym_id UUID NOT NULL CONSTRAINT fk_task_item_gym REFERENCES gyms(gym_id),
    member_id UUID NOT NULL,
    status task_status NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0
        CONSTRAINT task_item_attempts_non_negative CHECK (attempt_count >= 0),
    error_message TEXT,
    old_item_id UUID,
    new_item_id UUID,
    target_price_id UUID
        CONSTRAINT fk_task_item_target_price
        REFERENCES membership_plan_prices_unfiltered(price_id),
    prorate BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    PRIMARY KEY (task_item_id),
    CONSTRAINT fk_task_item_task_gym
        FOREIGN KEY (task_id, gym_id)
        REFERENCES tasks (task_id, gym_id),
    CONSTRAINT fk_task_item_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_task_item_old_membership_gym
        FOREIGN KEY (old_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),
    CONSTRAINT fk_task_item_new_membership_gym
        FOREIGN KEY (new_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id)
);

CREATE INDEX idx_task_items_task ON task_items (task_id);
CREATE INDEX idx_task_items_old_membership ON task_items (old_item_id)
    WHERE old_item_id IS NOT NULL;
CREATE INDEX idx_task_items_new_membership ON task_items (new_item_id)
    WHERE new_item_id IS NOT NULL;
