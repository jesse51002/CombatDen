-- Claim exactly one send. Runs inside the CALLER's transaction, so a
-- rolled-back operation (an employee insert that failed) un-sends its email
-- for free. ON CONFLICT on the idempotency key is the whole no-duplicates
-- mechanism: a double-clicked button, a retried request, and a re-run sweep
-- all collide here and only one row survives. No RETURNING row means the
-- send was already claimed.
INSERT INTO email_log (
    gym_id,
    kind,
    subject_id,
    idempotency_key,
    status,
    payload
)
VALUES (
    CAST(:gym_id AS UUID),
    CAST(:kind AS email_kind),
    CAST(:subject_id AS UUID),
    :idempotency_key,
    CAST(:status AS email_status),
    CAST(:payload AS JSONB)
)
ON CONFLICT (idempotency_key) DO NOTHING
RETURNING email_id
