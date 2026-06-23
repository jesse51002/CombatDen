-- Insert a start request's membership rows in ONE multi-row statement (all
-- pending rows appear atomically, or none). The DB generates each row's
-- item_id (PK default uuid_generate_v4()); we RETURNING them in row order so
-- the caller tracks every row individually — including multiple rows on the
-- same (member, plan) (e.g. a 5-pack and a 10-pack of one one-time plan at
-- different prices), each of which gets its OWN distinct id. A one_time / trial
-- pack bought N at once is ONE row with quantity = N (not N rows).
-- stripe_sync_status is parameterized per row so the real start inserts
-- 'not_added' (pending add the engine then converges) while a start PREVIEW
-- inserts 'preview_add' (the preview build sees it; the real path excludes it
-- so it can never bill, and the preview deletes it afterward). Arrays are bound
-- and CAST (never a bind followed directly by a double-colon cast — asyncpg
-- cannot bind that form).
INSERT INTO member_memberships_unfiltered (
    member_id, paid_by_member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, total_price, quantity, stripe_sync_status
)
SELECT
    u.member_id, u.paid_by_member_id, u.gym_id, u.plan_id, u.price_id,
    u.start_date, u.end_date, u.last_paid_date, u.next_due_date,
    u.stripe_item_id, u.total_price, u.quantity,
    CAST(u.sync_status AS stripe_sync_status)
FROM unnest(
    CAST(:member_ids AS UUID[]),
    CAST(:paid_by_member_ids AS UUID[]),
    CAST(:gym_ids AS UUID[]),
    CAST(:plan_ids AS UUID[]),
    CAST(:price_ids AS UUID[]),
    CAST(:start_dates AS DATE[]),
    CAST(:end_dates AS DATE[]),
    CAST(:last_paid_dates AS DATE[]),
    CAST(:next_due_dates AS DATE[]),
    CAST(:stripe_item_ids AS TEXT[]),
    CAST(:total_prices AS INTEGER[]),
    CAST(:quantities AS INTEGER[]),
    CAST(:sync_statuses AS TEXT[])
) AS u(
    member_id, paid_by_member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, total_price, quantity, sync_status
)
RETURNING item_id
