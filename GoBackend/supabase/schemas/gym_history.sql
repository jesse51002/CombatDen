CREATE TABLE gym_history (
    gym_id UUID NOT NULL REFERENCES gyms(gym_id),
    date DATE NOT NULL,
    members_total INTEGER NOT NULL,
    members_churned INTEGER NOT NULL,
    members_gained INTEGER NOT NULL,
    members_retained INTEGER NOT NULL,
    revenue FLOAT NOT NULL,
    PRIMARY KEY (gym_id, date)
);

-- Enable Row Level Security
ALTER TABLE gym_history ENABLE ROW LEVEL SECURITY;

-- Policy: Gym owners can read their gym's history (read-only, backend generates data)
CREATE POLICY "Gym owners can view own gym history"
    ON gym_history
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_history.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );
