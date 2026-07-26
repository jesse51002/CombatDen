-- The ALL-TIME number of rows of this kind for this person, used as the
-- resend sequence inside the idempotency key.
--
-- Deliberately NOT the trailing-window count that backs the resend cap. The
-- two answer different questions and only one of them may reset:
--
--   * the CAP asks "how many in the last hour" — it must reset, or a person
--     could never be resent to again;
--   * the SEQUENCE asks "which send is this" — it must NEVER reset, because
--     it is what makes a deliberate resend a NEW idempotency key rather than
--     a collision with the original send.
--
-- Using the windowed count for both meant a resend more than an hour after
-- the original — i.e. the normal case, since "they say it never arrived"
-- reaches staff hours or days later — computed sequence 0 again, collided
-- with the original claim, hit ON CONFLICT DO NOTHING, and silently sent
-- nothing while answering 202.
--
-- Counts every claimed row regardless of status: a held or failed row still
-- consumed its sequence number, so reusing it would collide just the same.
SELECT count(*) AS total_count
FROM email_log
WHERE subject_id = CAST(:subject_id AS UUID)
  AND kind = CAST(:kind AS email_kind)
