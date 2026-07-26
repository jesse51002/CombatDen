-- Retryable failure: the attempt counter is what the sweep's ceiling reads.
UPDATE email_log
SET status = CAST('failed' AS email_status),
    attempts = attempts + 1,
    last_error = :last_error
WHERE email_id = CAST(:email_id AS UUID)
RETURNING email_id
