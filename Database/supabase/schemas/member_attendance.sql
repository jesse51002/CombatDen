-- Append-only log of member attendance at a specific class instance.
-- Each row points to a class_history row (the actual occurrence). When a covering
-- membership exists it is attributed to that membership/plan (set once at
-- check-in; the cycle-count query groups attendance by item_id, so a member
-- holding two packs on the same plan draws each down separately). An admin
-- (non-kiosk) check-in records even when the member has NO covering membership —
-- those rows carry NULL plan_id/item_id (no pack is drawn), which the
-- cycle-count / streak reads ignore. plan_id and item_id are therefore either
-- both set (covered) or both NULL (no-membership admin check-in).
CREATE TABLE member_attendance (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_attendance_gym REFERENCES gyms(gym_id),
    class_history_id UUID NOT NULL CONSTRAINT fk_attendance_class_history_id REFERENCES class_history(class_history_id),
    -- The membership row + plan that covered this check-in (billing attribution);
    -- NULL together when an admin check-in had no covering membership to attribute to.
    plan_id UUID,
    item_id UUID,
    PRIMARY KEY (log_id),
    UNIQUE (member_id, class_history_id),
    CONSTRAINT chk_attendance_membership_pair
        CHECK ((plan_id IS NULL) = (item_id IS NULL)),
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
