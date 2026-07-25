-- One lookup per send, on the hot path. A global suppression (gym_id NULL)
-- is a dead or hostile mailbox and blocks every gym; a gym-scoped one blocks
-- only that gym's mail. 'all' blocks everything; 'marketing' blocks only when
-- the KIND is marketing, which the caller passes as include_marketing.
SELECT 1 AS suppressed
FROM email_suppressions
WHERE lower(email) = lower(:email)
  AND (gym_id IS NULL OR gym_id = CAST(:gym_id AS UUID))
  AND (
        scope = 'all'
        OR (CAST(:include_marketing AS BOOLEAN) AND scope = 'marketing')
      )
LIMIT 1
