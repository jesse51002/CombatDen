-- Daily snapshot of activity-state counts. Backend-generated.
-- total_active / total_inactive are end-of-day balances; went_inactive /
-- became_active are deltas for the day.
CREATE TABLE gym_history (
    gym_id UUID NOT NULL CONSTRAINT fk_history_gym REFERENCES gyms(gym_id),
    date DATE NOT NULL,
    total_active INTEGER NOT NULL CHECK (total_active >= 0),
    total_inactive INTEGER NOT NULL CHECK (total_inactive >= 0),
    went_inactive INTEGER NOT NULL CHECK (went_inactive >= 0),
    became_active INTEGER NOT NULL CHECK (became_active >= 0),
    PRIMARY KEY (gym_id, date)
);
