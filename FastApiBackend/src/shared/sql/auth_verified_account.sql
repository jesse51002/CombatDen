-- Standalone "is there a CONFIRMED auth account for this email?" probe, for
-- routes that authorize a caller who has no gym_employees row yet (gym
-- create). The bound email is lowercased by the caller.
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows.
-- EXISTS cannot fan out.
SELECT EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = :email
      AND u.email_confirmed_at IS NOT NULL
) AS account_verified;
