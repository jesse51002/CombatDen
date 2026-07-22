-- Every member row bearing the caller's verified email, across gyms.
--
-- This is the member portal's ENTRY POINT: the app has a JWT and nothing
-- else, so it asks "who am I, and where?" before any member_id exists to
-- pass. members.email carries NO uniqueness constraint by design (a family
-- shares one inbox), so a parent's address legitimately matches several
-- rows — hence a list, and hence every other member route takes an explicit
-- member_id that is re-checked by verify_member_self.
--
-- The caller has already passed verify_verified_account, but this query
-- carries the confirmed-account predicate itself so it is safe on its own —
-- the codebase rule is that EVERY identity-resolving query proves the
-- account is confirmed. A scalar EXISTS, never a JOIN: auth.users is unique
-- on email only WHERE is_sso_user = false, so a join can fan out and
-- duplicate the member row.
--
-- The bound email is lowercased by the caller and never empty (a missing
-- claim is a 401 before this runs). COALESCE guards a NULL members.email so
-- the comparison is a hard false rather than NULL.
SELECT m.member_id,
       m.gym_id,
       m.first_name,
       m.last_name,
       m.photo_url,
       g.gym_name,
       g.logo_url AS gym_logo_url
FROM members m
JOIN gyms g ON g.gym_id = m.gym_id
WHERE COALESCE(lower(m.email), '') = :email
  AND EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE lower(u.email) = :email
        AND u.email_confirmed_at IS NOT NULL
  )
ORDER BY g.gym_name ASC, m.first_name ASC, m.last_name ASC, m.member_id ASC;
