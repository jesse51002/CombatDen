-- Terminal success. sent_at is set exactly when status becomes 'sent'
-- (the sent_matches_status check constraint), and the resolved address is
-- frozen here so the audit trail records where the mail REALLY went.
UPDATE email_log
SET status = CAST('sent' AS email_status),
    sent_at = now(),
    provider_message_id = :provider_message_id,
    recipient = :recipient,
    attempts = attempts + 1,
    last_error = NULL
WHERE email_id = CAST(:email_id AS UUID)
RETURNING email_id
