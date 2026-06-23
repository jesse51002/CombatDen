-- Append-only log of member attendance at a specific class instance.
-- Each row points to a class_history row (the actual occurrence) and is
-- attributed to the membership/plan that covered the check-in (set once by the
-- gated check-in service; the cycle-count query groups attendance by item_id,
-- so a member holding two packs on the same plan draws each down separately).
CREATE TABLE member_attendance (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_attendance_gym REFERENCES gyms(gym_id),
    class_history_id UUID NOT NULL CONSTRAINT fk_attendance_class_history_id REFERENCES class_history(class_history_id),
    -- The membership row + plan that covered this check-in (billing attribution).
    plan_id UUID NOT NULL,
    item_id UUID NOT NULL,
    PRIMARY KEY (log_id),
    UNIQUE (member_id, class_history_id),
    CONSTRAINT fk_attendance_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_attendance_class_history_gym
        FOREIGN KEY (class_history_id, gym_id)
        REFERENCES class_history (class_history_id, gym_id),
    CONSTRAINT fk_attendance_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans_unfiltered (plan_id, gym_id),
    CONSTRAINT fk_attendance_membership_member
        FOREIGN KEY (item_id, member_id)
        REFERENCES member_memberships_unfiltered (item_id, member_id)
);

CREATE INDEX idx_member_attendance_member_gym
    ON member_attendance (member_id, gym_id);

CREATE INDEX idx_member_attendance_class_history
    ON member_attendance (class_history_id);
