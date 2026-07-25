-- Insert all membership rows atomically. RETURNING (item_id, member_id, price_id)
-- lets the caller map generated ids back positionally (not by RETURNING order).
-- ON CONFLICT on idempotency_key (every real-start row -- one-time, trial AND recurring;
-- NULL preview rows unaffected) drops duplicates on retry; a shortfall vs expected count
-- signals a stale replay. This index is the only RACE-safe dedup: the recurring trigger
-- trg_recurring_no_active_memberships is a SELECT COUNT that two concurrent inserts both pass.
INSERT INTO member_memberships_unfiltered (
    member_id, paid_by_member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, total_price, quantity, stripe_sync_status,
    idempotency_key
)
SELECT
    u.member_id, u.paid_by_member_id, u.gym_id, u.plan_id, u.price_id,
    u.start_date, u.end_date, u.last_paid_date, u.next_due_date,
    u.stripe_item_id, u.total_price, u.quantity,
    CAST(u.sync_status AS stripe_sync_status),
    u.idempotency_key
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
    CAST(:sync_statuses AS TEXT[]),
    CAST(:idempotency_keys AS UUID[])
) AS u(
    member_id, paid_by_member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, total_price, quantity, sync_status,
    idempotency_key
)
ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
RETURNING item_id, member_id, price_id
