-- Resume detection for the reprice: the member's live row on the target
-- price for the same plan — the successor a prior attempt's DB phase
-- created (the old row is already cancelled, so the desired state is
-- written; the caller skips straight to the convergent sync). Reads the
-- unfiltered base: a pending ('not_added') successor must be found.
SELECT item_id
FROM member_memberships_unfiltered
WHERE member_id = :member_id
  AND gym_id = :gym_id
  AND plan_id = :plan_id
  AND price_id = :target_price_id
  AND cancel_date IS NULL
  AND stripe_sync_status NOT IN ('deleted', 'preview_add', 'preview_remove')
ORDER BY created_at DESC
LIMIT 1
