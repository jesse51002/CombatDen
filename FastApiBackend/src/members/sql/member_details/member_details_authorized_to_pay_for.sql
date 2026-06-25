-- The members :member_id is authorized to pay for (the "authorized to pay for"
-- roster), with their display profile. Newest authorization first. This is the
-- AUTHORIZATION roster (who they MAY pay for); the actual billing relationship
-- is the separate "pays for" list (member_memberships.paid_by_member_id).
SELECT
    m.member_id,
    m.first_name,
    m.last_name,
    m.photo_url
FROM member_authorized_payers ap
JOIN members m ON m.member_id = ap.member_id
WHERE ap.payer_member_id = :member_id
ORDER BY ap.created_at DESC
