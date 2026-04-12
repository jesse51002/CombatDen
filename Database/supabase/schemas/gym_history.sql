CREATE TABLE gym_history (
    gym_id UUID NOT NULL CONSTRAINT fk_history_gym REFERENCES gyms(gym_id),
    date DATE NOT NULL,
    members_total INTEGER NOT NULL CHECK (members_total >= 0),
    members_churned INTEGER NOT NULL CHECK (members_churned >= 0),
    members_gained INTEGER NOT NULL CHECK (members_gained >= 0),
    members_retained INTEGER NOT NULL CHECK (members_retained >= 0),
    revenue INTEGER NOT NULL CHECK (revenue >= 0),
    PRIMARY KEY (gym_id, date)
);
