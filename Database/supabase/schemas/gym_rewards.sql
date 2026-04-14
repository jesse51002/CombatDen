CREATE TABLE gym_rewards (
    reward_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_reward_gym REFERENCES gyms(gym_id),
    title VARCHAR NOT NULL CHECK (title <> ''),
    amount_off VARCHAR,
    image_url VARCHAR,
    point_cost INTEGER NOT NULL CHECK (point_cost > 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (reward_id),
    UNIQUE (reward_id, gym_id)
);
