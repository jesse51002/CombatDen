-- Resolve a member email + the gym branding for the template.
-- members.email is nullable by design (engagement-only members have no
-- address), so a member with no email yields no row and the send is skipped.
SELECT
    lower(m.email) AS email,
    m.first_name AS first_name,
    g.gym_name AS gym_name,
    g.logo_url AS logo_url
FROM members m
JOIN gyms g ON g.gym_id = m.gym_id
WHERE m.member_id = CAST(:subject_id AS UUID)
  AND m.gym_id = CAST(:gym_id AS UUID)
  AND m.email IS NOT NULL
