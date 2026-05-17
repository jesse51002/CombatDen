ALTER TABLE members ENABLE ROW LEVEL SECURITY;

-- Members can view their own row; gym staff can view all members at their gym
CREATE POLICY "Users and gym staff can view members"
    ON members
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR is_gym_admin_or_owner(members.gym_id)
    );

-- Members can update their own row (name/email/last_class etc.); gym staff can update any row at their gym
CREATE POLICY "Users and gym staff can update members"
    ON members
    FOR UPDATE
    USING (
        auth.uid() = user_id
        OR is_gym_admin_or_owner(members.gym_id)
    )
    WITH CHECK (
        auth.uid() = user_id
        OR is_gym_admin_or_owner(members.gym_id)
    );

-- Gym staff can insert members for their gym
CREATE POLICY "Gym staff can insert members"
    ON members
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(members.gym_id));

-- Identity columns stay immutable
REVOKE UPDATE (member_id, user_id, gym_id, created_at) ON TABLE members FROM authenticated;
