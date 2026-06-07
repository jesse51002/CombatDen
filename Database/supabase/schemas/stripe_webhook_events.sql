CREATE TABLE stripe_webhook_events (
    event_id VARCHAR NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_webhook_gym REFERENCES gyms(gym_id),
    event_type VARCHAR NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id)
);

-- Index: auditing/debugging by gym
CREATE INDEX idx_webhook_events_gym ON stripe_webhook_events (gym_id, processed_at DESC);
