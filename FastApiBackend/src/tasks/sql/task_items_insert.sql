-- Insert a task's work units in ONE multi-row statement ('pending').
INSERT INTO task_items (
    task_id,
    gym_id,
    member_id,
    old_item_id,
    target_price_id,
    proration_behavior
)
SELECT
    CAST(:task_id AS UUID),
    CAST(:gym_id AS UUID),
    member_id,
    old_item_id,
    target_price_id,
    proration_behavior
FROM unnest(
    CAST(:member_ids AS UUID[]),
    CAST(:old_item_ids AS UUID[]),
    CAST(:target_price_ids AS UUID[]),
    CAST(:proration_behaviors AS proration_behavior[])
) AS t(member_id, old_item_id, target_price_id, proration_behavior)
RETURNING task_item_id
