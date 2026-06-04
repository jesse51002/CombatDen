ALTER TABLE members ENABLE ROW LEVEL SECURITY;

-- Members can view their own row; gym staff can view all members at their gym.
-- No restrictive Stripe filter: engagement-only members have NULL billing
-- columns and must remain visible — billing columns are simply NULL for them.
CREATE POLICY "Users and gym staff can view members"
    ON members
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR is_gym_admin_or_owner(members.gym_id)
    );

-- Members can update their own identity row (name/email/last_class etc.);
-- gym staff can update any row at their gym.
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

-- Identity columns stay immutable (PK / FK / created_at).
REVOKE UPDATE (member_id, user_id, gym_id, created_at) ON TABLE members FROM authenticated;

-- Column-level Stripe gating. The merged contact / freeze / linkage / Stripe
-- billing columns are written by service_role only — never by the client.
-- This is a deliberate exception to the per-table Stripe-gating rule: `members`
-- mixes client-writable identity with service_role billing, gated per-column
-- instead of per-table (see Database/CLAUDE.md). The unified table replaces the
-- former service_role-only member_billing_profile table.
REVOKE INSERT, UPDATE (
    photo_url,
    phone,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    freeze_start_date,
    freeze_end_date,
    account_linked_to_id,
    stripe_customer_id,
    stripe_sub_id_month,
    stripe_payment_method_id,
    payment_type,
    card_brand,
    card_last_four,
    card_exp_month,
    card_exp_year,
    total_monthly_recurring_price
) ON TABLE members FROM authenticated;

-- Filtered billing view: read-only for clients (writes go to the members
-- table via service_role). security_invoker propagates members' RLS.
GRANT SELECT ON member_billing_profile TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON member_billing_profile FROM authenticated;
