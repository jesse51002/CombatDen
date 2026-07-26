-- Backs the per-person resend cap: how many of this kind have we written for
-- this person in the trailing window. Counts every claimed row regardless of
-- status, so a burst of failures cannot be used to bypass the cap.
SELECT count(*) AS recent_count
FROM email_log
WHERE subject_id = CAST(:subject_id AS UUID)
  AND kind = CAST(:kind AS email_kind)
  AND created_at > now() - make_interval(secs => :within_seconds)
