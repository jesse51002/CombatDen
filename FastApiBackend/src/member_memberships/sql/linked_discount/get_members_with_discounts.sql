SELECT member_id, linked_discount_id
FROM member_billing_profile
WHERE member_id = ANY(:member_ids)
  AND linked_discount_id IS NOT NULL
