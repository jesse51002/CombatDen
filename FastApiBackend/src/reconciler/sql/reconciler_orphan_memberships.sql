-- Orphaned pending memberships: rows a membership-start op inserted but never
-- confirmed on Stripe (NULL stripe_item_id, still 'not_added'). A crash between
-- the insert and the verified sync can strand one. The cleanup deletes such a
-- row only when its family lock is free (no op in flight); read from the
-- unfiltered base since the filtered view hides 'not_added'.
--
-- A pending row a TASK produced is NOT an orphan: a reprice's successor row
-- waits as 'not_added' between retry attempts (no lock held), and even a
-- FAILED reprice's successor is the member's only live membership — its old
-- row is already cancelled, so reaping the successor would erase the
-- membership entirely. The push sweep converges those rows to 'applied'
-- instead, after which they no longer match here anyway.
SELECT item_id, member_id, gym_id
FROM member_memberships_unfiltered
WHERE stripe_item_id IS NULL
  AND stripe_sync_status = 'not_added'
  AND NOT EXISTS (
      SELECT 1
      FROM task_items ti
      WHERE ti.new_item_id = member_memberships_unfiltered.item_id
        AND ti.status IN ('pending', 'running', 'failed')
  )
