INSERT INTO member_memberships_unfiltered (
    member_id, gym_id, plan_id, price_id,
    start_date, end_date, last_paid_date, next_due_date,
    stripe_item_id, prorate, total_price
)
VALUES (
    :member_id, :gym_id, :plan_id, :price_id,
    :start_date, :end_date, :last_paid_date, :next_due_date,
    :stripe_item_id, :prorate, :total_price
)
RETURNING item_id
