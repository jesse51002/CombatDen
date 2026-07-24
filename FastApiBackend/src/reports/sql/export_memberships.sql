-- Raw membership instances for the gym (the UNFILTERED base table, for
-- completeness -- includes not-yet-synced / preview rows the filtered view
-- hides).
SELECT
    mm.item_id,
    mm.member_id,
    mm.gym_id,
    mm.plan_id,
    mm.price_id,
    mm.paid_by_member_id,
    mm.start_date,
    mm.end_date,
    mm.cancel_date,
    mm.last_paid_date,
    mm.next_due_date,
    mm.stripe_item_id,
    mm.stripe_one_time_invoice_id,
    mm.total_price,
    mm.quantity,
    mm.stripe_sync_status,
    mm.idempotency_key,
    mm.created_at
FROM member_memberships_unfiltered mm
WHERE mm.gym_id = CAST(:gym_id AS UUID)
ORDER BY mm.created_at ASC, mm.item_id ASC
