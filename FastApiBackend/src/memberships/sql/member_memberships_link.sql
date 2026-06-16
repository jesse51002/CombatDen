-- Linking clears only what stays parent-consolidated — the child's own
-- subscription id and freeze window (per linked_account_no_subscription_or_freeze).
-- The child KEEPS its own saved card (stripe_payment_method_id + the card_*
-- cache + payment_type): every member may store a card; it just isn't used for
-- the family's recurring billing, which the paying parent covers.
UPDATE members
SET
    account_linked_to_id     = :parent_member_id,
    stripe_sub_id_month      = NULL,
    freeze_start_date        = NULL,
    freeze_end_date          = NULL
WHERE member_id = :member_id
RETURNING member_id
