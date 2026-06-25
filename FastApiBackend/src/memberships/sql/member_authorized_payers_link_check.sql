-- Pre-flight for adding an authorized payer: the candidate member (c) + the
-- prospective payer's (p) existence/gym, and whether the pair is already
-- authorized. The candidate and payer must share a gym (the authorization FKs
-- both ids to members within one gym).
SELECT
    c.member_id,
    c.gym_id AS candidate_gym_id,
    p.member_id AS payer_member_id,
    p.gym_id AS payer_gym_id,
    EXISTS (
        SELECT 1
        FROM member_authorized_payers ap
        WHERE ap.member_id = c.member_id
          AND ap.payer_member_id = :payer_member_id
    ) AS already_authorized
FROM members c
LEFT JOIN members p ON p.member_id = :payer_member_id
WHERE c.member_id = :member_id
