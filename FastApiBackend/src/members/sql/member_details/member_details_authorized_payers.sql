-- The members authorized to pay for :member_id (the "authorized payers"
-- roster), with their display profile. Newest authorization first.
SELECT
    m.member_id,
    m.first_name,
    m.last_name,
    m.photo_url
FROM member_authorized_payers ap
JOIN members m ON m.member_id = ap.payer_member_id
WHERE ap.member_id = :member_id
ORDER BY ap.created_at DESC
