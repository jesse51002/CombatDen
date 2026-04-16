CREATE TABLE gym_classes_log (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_class_log_gym REFERENCES gyms_unfiltered(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_class_log_class_id REFERENCES gym_classes(class_id),
    plan_id UUID NOT NULL CONSTRAINT fk_class_log_plan_id REFERENCES membership_plans_unfiltered(plan_id),
    item_id UUID NOT NULL,
    instructor_id UUID,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (log_id),
    CONSTRAINT fk_class_log_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id),
    CONSTRAINT fk_class_log_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_log_membership_item
        FOREIGN KEY (item_id, crm_user_id)
        REFERENCES member_memberships_unfiltered (item_id, crm_user_id),
    CONSTRAINT fk_class_log_instructor
        FOREIGN KEY (instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);
