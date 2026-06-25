-- For the start op (_check_links): each requested member's existence + gym +
-- whether the request's payer is an authorized payer for them. One row per
-- found member; a requested id with no row does not exist.
SELECT
    m.member_id,
    m.gym_id,
    EXISTS (
        SELECT 1
        FROM member_authorized_payers ap
        WHERE ap.member_id = m.member_id
          AND ap.payer_member_id = :payer_member_id
    ) AS authorized
FROM members m
WHERE m.member_id = ANY(CAST(:member_ids AS UUID[]))
