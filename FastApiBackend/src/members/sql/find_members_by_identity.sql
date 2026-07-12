-- Duplicate-member gate for POST /members. Matches existing members at the
-- same gym whose first name, last name, AND email all match the request
-- case- and surrounding-whitespace-insensitively. Only runs for a non-null
-- request email; a member with a NULL email can never match (no reliable
-- identity to dedupe on).
SELECT
    member_id,
    first_name,
    last_name,
    email,
    photo_url
FROM members
WHERE gym_id = CAST(:gym_id AS UUID)
    AND lower(trim(first_name)) = lower(trim(CAST(:first_name AS VARCHAR)))
    AND lower(trim(last_name)) = lower(trim(CAST(:last_name AS VARCHAR)))
    AND email IS NOT NULL
    AND lower(trim(email)) = lower(trim(CAST(:email AS VARCHAR)))
