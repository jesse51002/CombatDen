INSERT INTO stripe_webhook_events (
    event_id,
    gym_id,
    event_type
)
VALUES (
    :event_id,
    :gym_id,
    :event_type
)
ON CONFLICT (event_id) DO NOTHING
RETURNING event_id
