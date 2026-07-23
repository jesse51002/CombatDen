-- The member-SELF identity probe: one row per member_id carrying everything
-- verify_member_self needs to rule — no row at all is a 404, a falsy flag is
-- a 403. The member's gym_id comes back so the caller can additionally scope
-- the match to a path gym (one email must not reach a same-named member at an
-- unrelated gym).
--
-- COALESCE guards a NULL members.email (a member row need not carry one) so
-- the comparison is a hard false rather than NULL. The bound email is
-- lowercased by the caller and is never empty (a missing claim is a 401
-- before this query runs).
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and
-- duplicate the member. EXISTS cannot fan out.
SELECT m.gym_id,
       (COALESCE(lower(m.email), '') = :email) AS email_matches,
       EXISTS (
           -- Pinned to the CALLER's own account (u.id = :caller_id, the JWT
           -- sub): the caller's OWN account must be confirmed, not just some
           -- account on this email. Email equality kept as defense in depth.
           SELECT 1
           FROM auth.users u
           WHERE u.id = CAST(:caller_id AS UUID)
             AND lower(u.email) = :email
             AND u.email_confirmed_at IS NOT NULL
       ) AS account_verified
FROM members m
WHERE m.member_id = CAST(:member_id AS UUID)
LIMIT 1;
