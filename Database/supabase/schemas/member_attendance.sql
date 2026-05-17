-- Append-only log of member attendance at a specific class instance.
-- Each row points to a class_history row (the actual occurrence).
CREATE TABLE member_attendance (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_attendance_gym REFERENCES gyms(gym_id),
    class_history_id UUID NOT NULL CONSTRAINT fk_attendance_class_history_id REFERENCES class_history(class_history_id),
    PRIMARY KEY (log_id),
    UNIQUE (member_id, class_history_id),
    CONSTRAINT fk_attendance_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_attendance_class_history_gym
        FOREIGN KEY (class_history_id, gym_id)
        REFERENCES class_history (class_history_id, gym_id)
);

CREATE INDEX idx_member_attendance_member_gym
    ON member_attendance (member_id, gym_id);

CREATE INDEX idx_member_attendance_class_history
    ON member_attendance (class_history_id);
