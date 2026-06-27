-- First/last name for a set of members, by id. Labels the per-payer entries of
-- the cancel / remove-authorization cost preview.
SELECT member_id,
       first_name,
       last_name
FROM members
WHERE member_id = ANY(CAST(:member_ids AS UUID[]))
