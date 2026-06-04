SELECT
    mbp.member_id,
    m.first_name,
    m.last_name,
    mbp.photo_url
FROM member_billing_profile mbp
JOIN members m ON m.member_id = mbp.member_id
WHERE mbp.gym_id = :gym_id
