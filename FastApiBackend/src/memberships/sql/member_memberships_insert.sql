-- Insert a start request's membership rows in ONE multi-row statement (all
-- pending rows appear atomically, or none). The DB generates each row's
-- item_id (PK default uuid_generate_v4()); we RETURNING item_id WITH its
-- (member_id, price_id) so the caller maps each generated id back to its row by
-- that key (unique within one request via the dedup) — NOT by RETURNING order,
-- which PostgreSQL streams in insert order for this INSERT … SELECT but does not
-- contractually guarantee. That covers multiple rows on the same (member, plan)
-- (e.g. a 5-pack and a 10-pack of one one-time plan at DIFFERENT prices), each
-- of which gets its OWN distinct id. A one_time / trial pack bought N at once is
-- ONE row with quantity = N (not N rows).
-- stripe_sync_status is parameterized per row so the real start inserts
-- 'not_added' (pending add the engine then converges) while a start PREVIEW
-- inserts 'preview_add' (the preview build sees it; the real path excludes it
-- so it can never bill, and the preview deletes it afterward). Arrays are bound
-- and CAST (never a bind followed directly by a double-colon cast — asyncpg
-- cannot bind that form).
-- idempotency_key (C-086): the start op stamps a deterministic per-row key on
-- ONE-TIME / TRIAL real-start rows (NULL for recurring + preview rows), so a
-- retried start request reproduces the same keys. ON CONFLICT on the partial
-- unique index (idx_member_memberships_idempotency_key) DROPS the retry's
-- duplicate rows instead of stacking 2N membership rows for one payment; the
-- WHERE predicate matches the partial index so the NULL-key rows are never
-- affected by the clause. A retry that drops rows returns FEWER rows than it
-- asked to insert — the caller (_crm_insert) detects that shortfall and rejects
-- the replay rather than re-discounting / re-charging the original rows.
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
