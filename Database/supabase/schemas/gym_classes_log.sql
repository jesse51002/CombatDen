CREATE TABLE gym_classes_log (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_class_log_gym REFERENCES gyms(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_class_log_class_id REFERENCES gym_classes(class_id),
    plan_id UUID NOT NULL CONSTRAINT fk_class_log_plan_id REFERENCES membership_plans(plan_id),
    instructor_id UUID,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (log_id),
    CONSTRAINT fk_class_log_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id),
    CONSTRAINT fk_class_log_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_log_membership
        FOREIGN KEY (crm_user_id, gym_id, plan_id)
        REFERENCES member_memberships (crm_user_id, gym_id, plan_id),
    CONSTRAINT fk_class_log_instructor
        FOREIGN KEY (instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE gym_classes_log ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own class logs OR gym staff can read logs from their gyms
CREATE POLICY "Users and gym staff can view class logs"
    ON gym_classes_log
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(gym_classes_log.gym_id)
    );

-- Policy: Gym staff can insert class logs
CREATE POLICY "Gym staff can insert class logs"
    ON gym_classes_log
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_classes_log.gym_id));

-- Column-level permissions: logs are immutable
REVOKE UPDATE ON TABLE gym_classes_log FROM authenticated;
