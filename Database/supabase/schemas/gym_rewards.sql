CREATE TABLE gym_rewards (
    reward_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_reward_gym REFERENCES gyms(gym_id),
    title VARCHAR NOT NULL CHECK (title <> ''),
    -- The reward's value label/badge, e.g. 'Free', '30% off'. Rendered as the
    -- prominent price tag on the member-app reward card. NOT NULL — every
    -- reward has a badge; writers fill 'Free' when none is provided.
    price_label VARCHAR NOT NULL,
    -- NOT NULL — every reward has an image (the points-store card leans on
    -- it); writers fill the platform default (settings.default_reward_image_url
    -- in FastApiBackend) whenever none is provided.
    image_url VARCHAR NOT NULL,
    point_cost INTEGER NOT NULL CHECK (point_cost > 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (reward_id),
    UNIQUE (reward_id, gym_id)
);
