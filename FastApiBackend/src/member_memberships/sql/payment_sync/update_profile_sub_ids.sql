UPDATE members
SET stripe_sub_id_month = :stripe_sub_id_month
WHERE member_id = :member_id
