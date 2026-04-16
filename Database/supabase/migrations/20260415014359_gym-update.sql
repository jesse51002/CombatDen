ALTER TABLE public.gym_class_schedules DROP CONSTRAINT gym_class_schedules_recurring_unit_check;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_discount_type_check;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_duration_check;
ALTER TABLE public.gym_employees DROP CONSTRAINT gym_employees_employee_type_check;
ALTER TABLE public.gyms_unfiltered DROP CONSTRAINT gyms_unfiltered_stripe_onboarding_status_check;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_duration_unit_check;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_plan_type_check;
ALTER TABLE public.gym_class_exceptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gym employees can view exceptions" ON public.gym_class_exceptions FOR SELECT USING (public.is_gym_employee(gym_id));
CREATE POLICY "Gym staff can insert exceptions" ON public.gym_class_exceptions FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Gym staff can update exceptions" ON public.gym_class_exceptions FOR UPDATE USING (public.is_gym_admin_or_owner(gym_id)) WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view exceptions" ON public.gym_class_exceptions FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_exceptions.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));
ALTER TABLE public.gym_class_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_recurring_unit_check CHECK (recurring_unit::text = ANY (ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying]::text[]));
CREATE TRIGGER trg_enforce_no_schedule_gaps AFTER INSERT OR DELETE OR UPDATE ON public.gym_class_schedules FOR EACH ROW EXECUTE FUNCTION public.check_no_schedule_gaps();
CREATE POLICY "Gym employees can view schedules" ON public.gym_class_schedules FOR SELECT USING (public.is_gym_employee(gym_id));
CREATE POLICY "Gym staff can insert schedules" ON public.gym_class_schedules FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Gym staff can update schedules" ON public.gym_class_schedules FOR UPDATE USING (public.is_gym_admin_or_owner(gym_id)) WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view schedules" ON public.gym_class_schedules FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.gym_classes
  WHERE ((gym_classes.class_id = gym_class_schedules.class_id) AND (gym_classes.is_active = true)))) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_schedules.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));
ALTER TABLE public.gym_classes ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_check_class_plan_ids_gym_match BEFORE INSERT OR UPDATE OF allowed_plan_ids ON public.gym_classes FOR EACH ROW EXECUTE FUNCTION public.check_class_plan_ids_gym_match();
CREATE POLICY "Gym employees can view classes" ON public.gym_classes FOR SELECT USING (public.is_gym_employee(gym_id));
CREATE POLICY "Gym staff can insert classes" ON public.gym_classes FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Gym staff can update classes" ON public.gym_classes FOR UPDATE USING (public.is_gym_admin_or_owner(gym_id)) WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view classes" ON public.gym_classes FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_classes.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));
ALTER TABLE public.gym_classes_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gym staff can insert class logs" ON public.gym_classes_log FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Users and gym staff can view class logs" ON public.gym_classes_log FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.gym_discounts_unfiltered ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_discount_type_check CHECK (discount_type::text = ANY (ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying]::text[]));
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_duration_check CHECK (duration::text = ANY (ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying]::text[]));
CREATE TRIGGER trg_enforce_linked_discount_sequence_delete BEFORE DELETE ON public.gym_discounts_unfiltered FOR EACH ROW WHEN (old.discount_type::text = 'linked'::text) EXECUTE FUNCTION public.enforce_linked_discount_sequence();
CREATE POLICY "Gym staff can view discounts" ON public.gym_discounts_unfiltered FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY hide_incomplete_stripe_records ON public.gym_discounts_unfiltered AS RESTRICTIVE FOR SELECT TO authenticated USING ((stripe_coupon_id IS NOT NULL));
ALTER TABLE public.gym_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_employee_type_check CHECK (employee_type::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying]::text[]));
CREATE UNIQUE INDEX unique_employee_user_gym ON public.gym_employees (user_id, gym_id) WHERE user_id IS NOT NULL;
CREATE POLICY "Employees can view gym staff" ON public.gym_employees FOR SELECT USING (public.is_gym_employee(gym_id));
CREATE POLICY "Owners and admins can insert employees" ON public.gym_employees FOR INSERT TO authenticated WITH CHECK ((public.is_gym_admin_or_owner(gym_id) OR (((employee_type)::text = 'owner'::text) AND (user_id = auth.uid()) AND (NOT public.gym_has_owner(gym_id)))));
CREATE POLICY "Owners and admins can update employees" ON public.gym_employees FOR UPDATE USING (public.is_gym_admin_or_owner(gym_id)) WITH CHECK (public.is_gym_admin_or_owner(gym_id));
ALTER TABLE public.gym_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gym staff can view own gym history" ON public.gym_history FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
ALTER TABLE public.gym_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gym staff can insert rewards" ON public.gym_rewards FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Gym staff can update rewards" ON public.gym_rewards FOR UPDATE USING (public.is_gym_admin_or_owner(gym_id)) WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Gym staff can view rewards" ON public.gym_rewards FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view active rewards" ON public.gym_rewards FOR SELECT USING (((is_active = true) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_rewards.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_unfiltered_stripe_onboarding_status_check CHECK (stripe_onboarding_status::text = ANY (ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying]::text[]));
ALTER TABLE public.member_memberships_unfiltered ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_recurring_chronological_start_date BEFORE INSERT ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_chronological_start_date();
CREATE TRIGGER trg_recurring_no_active_memberships BEFORE INSERT ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_active_memberships();
CREATE POLICY "Gym staff can view memberships" ON public.member_memberships_unfiltered FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view own memberships" ON public.member_memberships_unfiltered FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = member_memberships_unfiltered.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))));
CREATE POLICY hide_incomplete_stripe_records ON public.member_memberships_unfiltered AS RESTRICTIVE FOR SELECT TO authenticated USING ((stripe_item_id IS NOT NULL));
ALTER TABLE public.membership_plan_prices_unfiltered ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX idx_max_one_active_price_per_plan ON public.membership_plan_prices_unfiltered (plan_id) WHERE is_active = true;
CREATE POLICY "Gym staff can view plan prices" ON public.membership_plan_prices_unfiltered FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view plan prices" ON public.membership_plan_prices_unfiltered FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plan_prices_unfiltered.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));
CREATE POLICY hide_incomplete_stripe_records ON public.membership_plan_prices_unfiltered AS RESTRICTIVE FOR SELECT TO authenticated USING ((stripe_price_id IS NOT NULL));
ALTER TABLE public.membership_plans_unfiltered ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_duration_unit_check CHECK (duration_unit::text = ANY (ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying]::text[]));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_plan_type_check CHECK (plan_type::text = ANY (ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying]::text[]));
CREATE POLICY "Gym staff can view plans" ON public.membership_plans_unfiltered FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Members can view gym plans" ON public.membership_plans_unfiltered FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plans_unfiltered.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));
CREATE POLICY hide_incomplete_stripe_records ON public.membership_plans_unfiltered AS RESTRICTIVE FOR SELECT TO authenticated USING ((stripe_product_id IS NOT NULL));
ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_webhook_events_gym ON public.stripe_webhook_events (gym_id, processed_at DESC);
ALTER TABLE public.user_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gym staff can insert activities" ON public.user_activities FOR INSERT TO authenticated WITH CHECK (public.is_gym_admin_or_owner(gym_id));
CREATE POLICY "Users and gym staff can view activities" ON public.user_activities FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.user_gym_charges ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_charges_invoice ON public.user_gym_charges (invoice_id);
CREATE INDEX idx_charges_user_gym_time ON public.user_gym_charges (crm_user_id, gym_id, charge_time DESC);
CREATE INDEX idx_charges_gym_time ON public.user_gym_charges (gym_id, charge_time DESC);
CREATE POLICY "Users and gym staff can view charges" ON public.user_gym_charges FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles_unfiltered
  WHERE ((user_gym_profiles_unfiltered.crm_user_id = user_gym_charges.crm_user_id) AND (user_gym_profiles_unfiltered.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.user_gym_invoice_applied_discounts ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_applied_discounts_invoice ON public.user_gym_invoice_applied_discounts (invoice_id);
CREATE POLICY "Users and gym staff can view applied discounts" ON public.user_gym_invoice_applied_discounts FOR SELECT USING (((EXISTS ( SELECT 1
   FROM (public.user_gym_invoices inv
     JOIN public.user_gym_profiles_unfiltered p ON ((p.crm_user_id = inv.crm_user_id)))
  WHERE ((inv.invoice_id = user_gym_invoice_applied_discounts.invoice_id) AND (p.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.user_gym_invoice_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_line_items_invoice ON public.user_gym_invoice_line_items (invoice_id);
CREATE INDEX idx_line_items_item ON public.user_gym_invoice_line_items (item_id) WHERE item_id IS NOT NULL;
CREATE POLICY "Users and gym staff can view invoice line items" ON public.user_gym_invoice_line_items FOR SELECT USING (((EXISTS ( SELECT 1
   FROM (public.user_gym_invoices inv
     JOIN public.user_gym_profiles_unfiltered p ON ((p.crm_user_id = inv.crm_user_id)))
  WHERE ((inv.invoice_id = user_gym_invoice_line_items.invoice_id) AND (p.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.user_gym_invoices ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_invoices_user_gym_time ON public.user_gym_invoices (crm_user_id, gym_id, invoice_time DESC);
CREATE INDEX idx_invoices_gym_time ON public.user_gym_invoices (gym_id, invoice_time DESC);
CREATE POLICY "Users and gym staff can view invoices" ON public.user_gym_invoices FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles_unfiltered
  WHERE ((user_gym_profiles_unfiltered.crm_user_id = user_gym_invoices.crm_user_id) AND (user_gym_profiles_unfiltered.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
ALTER TABLE public.user_gym_profiles_unfiltered ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX idx_profiles_stripe_customer ON public.user_gym_profiles_unfiltered (stripe_customer_id);
CREATE UNIQUE INDEX unique_user_gym ON public.user_gym_profiles_unfiltered (user_id, gym_id) WHERE user_id IS NOT NULL;
CREATE TRIGGER trg_prevent_user_id_overwrite BEFORE UPDATE OF user_id ON public.user_gym_profiles_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_overwrite();
CREATE POLICY "Users and gym staff can view profiles" ON public.user_gym_profiles_unfiltered FOR SELECT USING (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));
CREATE POLICY hide_incomplete_stripe_records ON public.user_gym_profiles_unfiltered AS RESTRICTIVE FOR SELECT TO authenticated USING ((stripe_customer_id IS NOT NULL));
ALTER TABLE public.user_gym_reward_redemptions ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_reward_redemptions_user_gym_time ON public.user_gym_reward_redemptions (crm_user_id, gym_id, redeemed_at DESC);
CREATE POLICY "Users and gym staff can view reward redemptions" ON public.user_gym_reward_redemptions FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles_unfiltered
  WHERE ((user_gym_profiles_unfiltered.crm_user_id = user_gym_reward_redemptions.crm_user_id) AND (user_gym_profiles_unfiltered.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));
