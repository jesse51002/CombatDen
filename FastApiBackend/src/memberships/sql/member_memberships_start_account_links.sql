-- Link + gym state for every distinct member in a start request, in one read.
-- The start op NEVER links: each non-payer member must already be linked to
-- the request's payer, so the service only needs to verify the existing state.
SELECT
    member_id,
    gym_id,
    account_linked_to_id
FROM members
WHERE member_id = ANY(:member_ids)
