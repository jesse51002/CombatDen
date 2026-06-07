-- Insert a membership row. stripe_sync_status is parameterized so the real start
-- inserts 'not_added' (pending add the sync then converges) while a start PREVIEW
-- inserts 'preview_add' (the preview build sees it; the real path excludes it so it
-- can never bill, and the preview deletes it afterward). CAST for the enum bind.
INSERT INTO member_memberships_unfiltered (
    member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, prorate, total_price, stripe_sync_status
)
VALUES (
    :member_id, :gym_id, :plan_id, :price_id,
    :start_date, :end_date, :last_paid_date, :next_due_date,
    :stripe_item_id, :prorate, :total_price,
    CAST(:sync_status AS stripe_sync_status)
)
RETURNING item_id
