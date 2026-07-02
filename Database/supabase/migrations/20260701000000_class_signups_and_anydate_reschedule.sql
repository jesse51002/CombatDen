-- Hand-authored migration.
-- Two independent, additive/non-destructive changes reaching the schemas/
-- end state for class_signups and class_instance_exceptions:
--   * New table class_signups -- a member's reservation for a class occurrence
--     (NOT attendance; member_attendance is still the only attendance record).
--     Mirrors schemas/class_signups.sql + access_rules/class_signups.sql.
--   * class_instance_exceptions drops chk_instance_exception_new_date_future
--     (added by 20260628010000_class_scheduling_foundation.sql) -- new_date may
--     now be any date, not just strictly-future. original_date is only the
--     anchor the move is measured from, not a lower bound (see schemas/class_
--     instance_exceptions.sql's new_date comment).
-- No view selects from either table, so no view recreation is needed.

-- ============================================================
-- class_signups (mirrors schemas/class_signups.sql)
-- ============================================================

CREATE TABLE class_signups (
    signup_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_signup_gym REFERENCES gyms(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_class_signup_class_id REFERENCES gym_classes(class_id),
    member_id UUID NOT NULL,
    occurrence_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (signup_id),
    UNIQUE (class_id, member_id, occurrence_date),
    CONSTRAINT fk_class_signup_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_signup_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_class_signups_class_occurrence
    ON class_signups (class_id, occurrence_date);

CREATE INDEX idx_class_signups_member_gym
    ON class_signups (member_id, gym_id);

-- Access rules for class_signups (mirrors access_rules/class_signups.sql)
ALTER TABLE class_signups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users and gym staff can view class signups"
    ON class_signups
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = class_signups.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(class_signups.gym_id)
    );

-- Both staff and the member themselves may create / cancel a sign-up, but
-- that authorization (staff-for-any-gym-member OR member-for-self) is
-- enforced by the API's verify_can_view_member check, not by RLS -- unlike
-- member_attendance / class_history (staff-only INSERT policy), class_signups
-- has NO authenticated write policy at all: every write goes through the
-- backend's service_role connection.
REVOKE INSERT, UPDATE, DELETE ON TABLE class_signups FROM authenticated;

-- ============================================================
-- class_instance_exceptions: any-date reschedule
-- ============================================================

ALTER TABLE class_instance_exceptions
    DROP CONSTRAINT chk_instance_exception_new_date_future;
