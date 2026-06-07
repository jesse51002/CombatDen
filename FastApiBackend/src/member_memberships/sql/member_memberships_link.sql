UPDATE members
SET
    account_linked_to_id     = :parent_member_id,
    stripe_sub_id_month      = NULL,
    stripe_payment_method_id = NULL,
    freeze_start_date        = NULL,
    freeze_end_date          = NULL,
    payment_type             = NULL,
    card_brand               = NULL,
    card_last_four           = NULL,
    card_exp_month           = NULL,
    card_exp_year            = NULL
WHERE member_id = :member_id
RETURNING member_id
