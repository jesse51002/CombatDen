DELETE FROM member_authorized_payers
WHERE member_id = :id OR payer_member_id = :id
