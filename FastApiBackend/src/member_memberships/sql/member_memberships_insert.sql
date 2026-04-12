INSERT INTO member_memberships (
    item_id, crm_user_id, gym_id, plan_id, price_id,
    start_date, end_date, next_due_date,
    discount_ids, stripe_item_id, prorate, total_price
)
VALUES (
    :item_id, :crm_user_id, :gym_id, :plan_id, :price_id,
    :start_date, :end_date, :next_due_date,
    :discount_ids, :stripe_item_id, :prorate, :total_price
)
