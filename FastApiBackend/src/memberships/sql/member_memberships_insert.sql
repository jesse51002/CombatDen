-- Insert a start request's membership rows in ONE multi-row statement (all
-- pending rows appear atomically, or none). stripe_sync_status is
-- parameterized per row so the real start inserts 'not_added' (pending add
-- the engine then converges) while a start PREVIEW inserts 'preview_add'
-- (the preview build sees it; the real path excludes it so it can never
-- bill, and the preview deletes it afterward). Arrays are bound and CAST
-- (never a bind followed directly by a double-colon cast — asyncpg cannot
-- bind that form).
INSERT INTO member_memberships_unfiltered (
    member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, prorate, total_price, stripe_sync_status
)
SELECT
    u.member_id, u.gym_id, u.plan_id, u.price_id,
    u.start_date, u.end_date, u.last_paid_date, u.next_due_date,
    u.stripe_item_id, u.prorate, u.total_price,
    CAST(u.sync_status AS stripe_sync_status)
FROM unnest(
    CAST(:member_ids AS UUID[]),
    CAST(:gym_ids AS UUID[]),
    CAST(:plan_ids AS UUID[]),
    CAST(:price_ids AS UUID[]),
    CAST(:start_dates AS DATE[]),
    CAST(:end_dates AS DATE[]),
    CAST(:last_paid_dates AS DATE[]),
    CAST(:next_due_dates AS DATE[]),
    CAST(:stripe_item_ids AS TEXT[]),
    CAST(:prorates AS BOOLEAN[]),
    CAST(:total_prices AS INTEGER[]),
    CAST(:sync_statuses AS TEXT[])
) AS u(
    member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, prorate, total_price, sync_status
)
RETURNING item_id, member_id, plan_id
