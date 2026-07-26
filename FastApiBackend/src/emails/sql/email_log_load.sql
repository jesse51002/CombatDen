SELECT
    email_id,
    gym_id,
    kind,
    subject_id,
    recipient,
    idempotency_key,
    status,
    payload,
    provider_message_id,
    attempts,
    last_error,
    created_at,
    sent_at
FROM email_log
WHERE email_id = CAST(:email_id AS UUID)
