-- Terminal-by-policy (currently 'suppressed'): the send will never be
-- attempted again. sent_at stays NULL, which the sent_matches_status check
-- requires for any status other than 'sent'.
UPDATE email_log
SET status = CAST(:status AS email_status),
    recipient = :recipient,
    last_error = :last_error
WHERE email_id = CAST(:email_id AS UUID)
RETURNING email_id
