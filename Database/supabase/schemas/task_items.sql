-- One work unit of a task (see tasks.sql): one membership-level operation,
-- tracked individually — status, attempts, error, and the old-row → new-row
-- linkage the operation produced. The reprice executor stamps new_item_id
-- only AFTER the reprice op fully converges (the successor is synced to
-- Stripe and marked applied), in a separate post-reprice transaction — so
-- a non-NULL new_item_id marks a fully-completed item (a retried item that
-- already carries one has nothing left to do). A reprice that crashes or
-- fails mid-op leaves new_item_id NULL and its partial not_added successor
-- reverted, so a not_added successor is never referenced by a task_items
-- row.
--
-- Op parameters are TYPED columns (not JSONB): membership_reprice uses
-- target_price_id + proration_behavior. A future task_type adds its own
-- nullable columns.

-- How the reprice's recurring charge is handled relative to the billing
-- anchor. The same enum the request layer + sync engine speak end-to-end;
-- mapped to Stripe's proration_behavior only at the Stripe SDK boundary.
-- task_items is the sole table that stores it (declared here, its owner).
CREATE TYPE proration_behavior AS ENUM (
    'prorate_to_anchor',
    'no_charge'
);

CREATE TABLE task_items (
    task_item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL CONSTRAINT fk_task_item_task REFERENCES tasks(task_id),
    gym_id UUID NOT NULL CONSTRAINT fk_task_item_gym REFERENCES gyms(gym_id),
    member_id UUID NOT NULL,
    status task_status NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0
        CONSTRAINT task_item_attempts_non_negative CHECK (attempt_count >= 0),
    error_message TEXT,

    -- The membership row the operation acts on (reprice: the row being
    -- replaced).
    old_item_id UUID,

    -- The successor membership row the operation produced. Stamped by the
    -- executor only after the reprice fully converges (a separate
    -- post-reprice transaction), so it is set only on a completed item.
    new_item_id UUID,

    -- membership_reprice parameters.
    target_price_id UUID
        CONSTRAINT fk_task_item_target_price
        REFERENCES membership_plan_prices_unfiltered(price_id),
    proration_behavior proration_behavior,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,

    PRIMARY KEY (task_item_id),

    -- The parent task must belong to the same gym.
    CONSTRAINT fk_task_item_task_gym
        FOREIGN KEY (task_id, gym_id)
        REFERENCES tasks (task_id, gym_id),

    -- The member must belong to the same gym.
    CONSTRAINT fk_task_item_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    -- Both membership rows must belong to the same gym.
    CONSTRAINT fk_task_item_old_membership_gym
        FOREIGN KEY (old_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),
    CONSTRAINT fk_task_item_new_membership_gym
        FOREIGN KEY (new_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id)
);

CREATE INDEX idx_task_items_task ON task_items (task_id);

-- The in-task guard ("is this membership referenced by an unfinished item?")
-- probes by membership row id on pending/running items
-- (task_items_active_for_memberships.sql).
CREATE INDEX idx_task_items_old_membership ON task_items (old_item_id)
    WHERE old_item_id IS NOT NULL;
CREATE INDEX idx_task_items_new_membership ON task_items (new_item_id)
    WHERE new_item_id IS NOT NULL;
