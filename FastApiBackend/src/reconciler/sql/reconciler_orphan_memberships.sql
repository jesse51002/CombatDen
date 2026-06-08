-- Orphaned pending memberships: rows a membership-start op inserted but never
-- confirmed on Stripe (NULL stripe_item_id, still 'not_added'). A crash between
-- the insert and the verified sync can strand one. The cleanup deletes such a
-- row only when its family lock is free (no op in flight); read from the
-- unfiltered base since the filtered view hides 'not_added'.
SELECT item_id, member_id, gym_id
FROM member_memberships_unfiltered
WHERE stripe_item_id IS NULL
  AND stripe_sync_status = 'not_added'
