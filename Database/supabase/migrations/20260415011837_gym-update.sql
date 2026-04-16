ALTER TABLE public.gym_class_exceptions DROP CONSTRAINT fk_exception_gym;
DROP TABLE public.gym_class_exceptions;
ALTER TABLE public.gym_class_schedules DROP CONSTRAINT fk_schedule_gym;
ALTER TABLE public.gym_class_schedules DROP CONSTRAINT gym_class_schedules_recurring_unit_check;
DROP TABLE public.gym_class_schedules;
ALTER TABLE public.gym_classes_log DROP CONSTRAINT fk_class_log_gym;
DROP TABLE public.gym_classes_log;
ALTER TABLE public.gym_classes DROP CONSTRAINT fk_class_gym;
DROP TABLE public.gym_classes;
DROP VIEW IF EXISTS public.gym_discounts;
ALTER TABLE public.user_gym_invoice_applied_discounts DROP CONSTRAINT IF EXISTS fk_applied_discount_discount_gym;
ALTER TABLE public.user_gym_profiles_unfiltered DROP CONSTRAINT IF EXISTS fk_profile_linked_discount;
ALTER TABLE public.user_gym_profiles_unfiltered DROP CONSTRAINT IF EXISTS fk_profile_linked_discount_gym;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT fk_discount_gym;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_discount_type_check;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_duration_check;
DROP TABLE public.gym_discounts_unfiltered;
ALTER TABLE public.gym_employees DROP CONSTRAINT fk_employee_gym;
ALTER TABLE public.gym_employees DROP CONSTRAINT gym_employees_employee_type_check;
DROP TABLE public.gym_employees;
ALTER TABLE public.gym_history DROP CONSTRAINT fk_history_gym;
DROP TABLE public.gym_history;
ALTER TABLE public.user_gym_reward_redemptions DROP CONSTRAINT IF EXISTS fk_redemption_reward;
ALTER TABLE public.user_gym_reward_redemptions DROP CONSTRAINT IF EXISTS fk_redemption_reward_gym;
ALTER TABLE public.gym_rewards DROP CONSTRAINT fk_reward_gym;
DROP TABLE public.gym_rewards;
DROP VIEW IF EXISTS public.member_memberships_status;
DROP VIEW IF EXISTS public.member_memberships;
ALTER TABLE public.user_gym_invoice_line_items DROP CONSTRAINT IF EXISTS fk_line_item_membership_gym;
ALTER TABLE public.member_memberships_unfiltered DROP CONSTRAINT fk_membership_gym;
DROP TABLE public.member_memberships_unfiltered;
DROP VIEW IF EXISTS public.membership_plan_prices;
ALTER TABLE public.membership_plan_prices_unfiltered DROP CONSTRAINT fk_plan_price_gym;
DROP TABLE public.membership_plan_prices_unfiltered;
DROP VIEW IF EXISTS public.membership_plans;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT fk_plan_gym;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_duration_unit_check;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_plan_type_check;
DROP TABLE public.membership_plans_unfiltered;
ALTER TABLE public.stripe_webhook_events DROP CONSTRAINT fk_webhook_gym;
DROP TABLE public.stripe_webhook_events;
ALTER TABLE public.user_activities DROP CONSTRAINT fk_activity_gym;
DROP TABLE public.user_activities;
ALTER TABLE public.user_gym_charges DROP CONSTRAINT fk_charge_gym;
DROP TABLE public.user_gym_charges;
ALTER TABLE public.user_gym_invoice_applied_discounts DROP CONSTRAINT fk_applied_discount_gym;
DROP TABLE public.user_gym_invoice_applied_discounts;
ALTER TABLE public.user_gym_invoice_line_items DROP CONSTRAINT fk_line_item_gym;
DROP TABLE public.user_gym_invoice_line_items;
ALTER TABLE public.user_gym_invoices DROP CONSTRAINT fk_invoice_gym;
DROP TABLE public.user_gym_invoices;
ALTER TABLE public.user_gym_profiles_unfiltered DROP CONSTRAINT fk_profile_gym;
ALTER TABLE public.user_gym_reward_redemptions DROP CONSTRAINT fk_redemption_gym;
DROP TABLE public.user_gym_reward_redemptions;
DROP VIEW IF EXISTS public.user_gym_profiles;
DROP TABLE public.user_gym_profiles_unfiltered;
DROP POLICY "Gym staff can view own gym" ON public.gyms;
DROP TABLE public.gyms;
CREATE TABLE public.gym_class_exceptions (exception_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, schedule_id uuid NOT NULL, gym_id uuid NOT NULL, original_date date NOT NULL, is_cancelled boolean, new_class_time time without time zone, new_duration_minutes integer, new_max_capacity integer, new_instructor_id uuid, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT gym_class_exceptions_new_duration_minutes_check CHECK (new_duration_minutes > 0);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT gym_class_exceptions_new_max_capacity_check CHECK (new_max_capacity > 0);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT gym_class_exceptions_pkey PRIMARY KEY (exception_id);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT gym_class_exceptions_schedule_id_original_date_key UNIQUE (schedule_id, original_date);
CREATE TABLE public.gym_class_schedules (schedule_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, class_id uuid NOT NULL, gym_id uuid NOT NULL, class_time time without time zone NOT NULL, duration_minutes integer NOT NULL, recurring_unit character varying NOT NULL, recurring_interval integer DEFAULT 1 NOT NULL, sun boolean DEFAULT false NOT NULL, mon boolean DEFAULT false NOT NULL, tue boolean DEFAULT false NOT NULL, wed boolean DEFAULT false NOT NULL, thu boolean DEFAULT false NOT NULL, fri boolean DEFAULT false NOT NULL, sat boolean DEFAULT false NOT NULL, sun_instructor_id uuid, mon_instructor_id uuid, tue_instructor_id uuid, wed_instructor_id uuid, thu_instructor_id uuid, fri_instructor_id uuid, sat_instructor_id uuid, is_cancelled boolean DEFAULT false NOT NULL, start_date date NOT NULL, end_date date, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_recurring_unit_check CHECK (recurring_unit::text = ANY (ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying]::text[]));
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_check CHECK (end_date IS NULL OR end_date >= start_date);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_check1 CHECK (recurring_unit::text <> 'weekly'::text OR sun OR mon OR tue OR wed OR thu OR fri OR sat);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_class_id_daterange_excl EXCLUDE USING gist (class_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_duration_minutes_check CHECK (duration_minutes > 0);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_pkey PRIMARY KEY (schedule_id);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT fk_exception_schedule_id FOREIGN KEY (schedule_id) REFERENCES public.gym_class_schedules(schedule_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_recurring_interval_check CHECK (recurring_interval > 0);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_schedule_id_gym_id_key UNIQUE (schedule_id, gym_id);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT fk_exception_schedule FOREIGN KEY (schedule_id, gym_id) REFERENCES public.gym_class_schedules(schedule_id, gym_id);
CREATE TABLE public.gym_classes (class_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, class_name character varying NOT NULL, class_description character varying, allowed_plan_ids jsonb, max_capacity integer, is_active boolean DEFAULT true NOT NULL, is_deleted boolean DEFAULT false NOT NULL, end_date date, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_class_id_gym_id_key UNIQUE (class_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_schedule_class FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id);
ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_class_name_check CHECK (class_name::text <> ''::text);
ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_max_capacity_check CHECK (max_capacity > 0);
ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_pkey PRIMARY KEY (class_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_schedule_class_id FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id);
CREATE TABLE public.gym_classes_log (log_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, crm_user_id uuid NOT NULL, gym_id uuid NOT NULL, class_id uuid NOT NULL, plan_id uuid NOT NULL, item_id uuid NOT NULL, instructor_id uuid, "time" timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_class FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_class_id FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT gym_classes_log_pkey PRIMARY KEY (log_id);
REVOKE UPDATE ON public.gym_classes_log FROM authenticated;
CREATE TABLE public.gym_discounts_unfiltered (discount_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, discount_name character varying NOT NULL, discount_type character varying NOT NULL, percentage_off double precision, dollar_off integer, membership_plan_id uuid, linked_discount_num integer, duration character varying NOT NULL, duration_in_months integer, is_deleted boolean DEFAULT false NOT NULL, stripe_coupon_id character varying, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_discount_type_check CHECK (discount_type::text = ANY (ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying]::text[]));
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_duration_check CHECK (duration::text = ANY (ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying]::text[]));
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT chk_duration_in_months CHECK (duration::text = 'repeating'::text AND duration_in_months IS NOT NULL OR duration::text <> 'repeating'::text AND duration_in_months IS NULL);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT chk_linked_discount_fields CHECK (discount_type::text = 'linked'::text AND membership_plan_id IS NOT NULL AND linked_discount_num IS NOT NULL AND dollar_off IS NOT NULL OR discount_type::text <> 'linked'::text AND membership_plan_id IS NULL AND linked_discount_num IS NULL);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_check CHECK (num_nonnulls(percentage_off, dollar_off) = 1);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_discount_id_gym_id_key UNIQUE (discount_id, gym_id);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_discount_name_check CHECK (discount_name::text <> ''::text);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_dollar_off_check CHECK (dollar_off > 0);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_duration_in_months_check CHECK (duration_in_months > 0);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key UNIQUE (gym_id, membership_plan_id, linked_discount_num);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_linked_discount_num_check CHECK (linked_discount_num > 0);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_percentage_off_check CHECK (percentage_off > 0::double precision AND percentage_off <= 100::double precision);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_pkey PRIMARY KEY (discount_id);
REVOKE INSERT, UPDATE ON public.gym_discounts_unfiltered FROM authenticated;
CREATE TABLE public.gym_employees (employee_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, user_id uuid, gym_id uuid NOT NULL, employee_type character varying NOT NULL, first_name character varying NOT NULL, last_name character varying NOT NULL, phone character varying, email character varying, employee_pic_url character varying, employee_public_description character varying, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_employee_type_check CHECK (employee_type::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying]::text[]));
ALTER TABLE public.gym_employees ADD CONSTRAINT fk_employee_user FOREIGN KEY (user_id) REFERENCES auth.users(id);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_employee_id_gym_id_key UNIQUE (employee_id, gym_id);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT fk_exception_instructor FOREIGN KEY (new_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_fri_instructor FOREIGN KEY (fri_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_mon_instructor FOREIGN KEY (mon_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_sat_instructor FOREIGN KEY (sat_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_sun_instructor FOREIGN KEY (sun_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_thu_instructor FOREIGN KEY (thu_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_tue_instructor FOREIGN KEY (tue_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_sched_wed_instructor FOREIGN KEY (wed_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_instructor FOREIGN KEY (instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_first_name_check CHECK (first_name::text <> ''::text);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_last_name_check CHECK (last_name::text <> ''::text);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_pkey PRIMARY KEY (employee_id);
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_user_id_gym_id_key UNIQUE (user_id, gym_id);
CREATE TABLE public.gym_history (gym_id uuid NOT NULL, date date NOT NULL, members_total integer NOT NULL, members_churned integer NOT NULL, members_gained integer NOT NULL, members_retained integer NOT NULL, revenue integer NOT NULL);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_members_churned_check CHECK (members_churned >= 0);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_members_gained_check CHECK (members_gained >= 0);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_members_retained_check CHECK (members_retained >= 0);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_members_total_check CHECK (members_total >= 0);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_pkey PRIMARY KEY (gym_id, date);
ALTER TABLE public.gym_history ADD CONSTRAINT gym_history_revenue_check CHECK (revenue >= 0);
CREATE TABLE public.gym_rewards (reward_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, title character varying NOT NULL, amount_off character varying, image_url character varying, point_cost integer NOT NULL, is_active boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.gym_rewards ADD CONSTRAINT gym_rewards_pkey PRIMARY KEY (reward_id);
ALTER TABLE public.gym_rewards ADD CONSTRAINT gym_rewards_point_cost_check CHECK (point_cost > 0);
ALTER TABLE public.gym_rewards ADD CONSTRAINT gym_rewards_reward_id_gym_id_key UNIQUE (reward_id, gym_id);
ALTER TABLE public.gym_rewards ADD CONSTRAINT gym_rewards_title_check CHECK (title::text <> ''::text);
CREATE TABLE public.gyms_unfiltered (gym_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_name character varying NOT NULL, gym_description character varying, timezone text DEFAULT 'America/Chicago'::text NOT NULL, stripe_account_id character varying, stripe_onboarding_status character varying DEFAULT 'not_started'::character varying NOT NULL);
ALTER TABLE public.gyms_unfiltered ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_timezone_valid CHECK ((now() AT TIME ZONE timezone) IS NOT NULL);
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_unfiltered_gym_name_check CHECK (gym_name::text <> ''::text);
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_unfiltered_pkey PRIMARY KEY (gym_id);
ALTER TABLE public.gym_class_exceptions ADD CONSTRAINT fk_exception_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT fk_schedule_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_classes ADD CONSTRAINT fk_class_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT fk_discount_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_employees ADD CONSTRAINT fk_employee_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_history ADD CONSTRAINT fk_history_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gym_rewards ADD CONSTRAINT fk_reward_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_unfiltered_stripe_onboarding_status_check CHECK (stripe_onboarding_status::text = ANY (ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying]::text[]));
REVOKE INSERT, UPDATE ON public.gyms_unfiltered FROM authenticated;
CREATE POLICY "Gym staff can view own gym" ON public.gyms_unfiltered FOR SELECT USING (public.is_gym_admin_or_owner(gym_id));
CREATE TABLE public.member_memberships_unfiltered (item_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, crm_user_id uuid NOT NULL, gym_id uuid NOT NULL, plan_id uuid NOT NULL, price_id uuid NOT NULL, start_date date NOT NULL, end_date date, cancel_date date, last_paid_date date, next_due_date date, discount_ids jsonb, stripe_item_id character varying, prorate boolean DEFAULT true NOT NULL, total_price integer NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT fk_membership_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT member_memberships_unfiltered_item_id_crm_user_id_key UNIQUE (item_id, crm_user_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_membership_item FOREIGN KEY (item_id, crm_user_id) REFERENCES public.member_memberships_unfiltered(item_id, crm_user_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT member_memberships_unfiltered_item_id_gym_id_key UNIQUE (item_id, gym_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT member_memberships_unfiltered_pkey PRIMARY KEY (item_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT member_memberships_unfiltered_total_price_check CHECK (total_price >= 0);
REVOKE UPDATE ON public.member_memberships_unfiltered FROM authenticated;
CREATE TABLE public.membership_plan_prices_unfiltered (price_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, plan_id uuid NOT NULL, gym_id uuid NOT NULL, stripe_price_id character varying, price integer NOT NULL, is_active boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT fk_plan_price_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT membership_plan_prices_unfiltered_pkey PRIMARY KEY (price_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT fk_membership_price FOREIGN KEY (price_id) REFERENCES public.membership_plan_prices_unfiltered(price_id);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT membership_plan_prices_unfiltered_price_check CHECK (price >= 0);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT membership_plan_prices_unfiltered_price_id_plan_id_key UNIQUE (price_id, plan_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT fk_membership_price_plan FOREIGN KEY (price_id, plan_id) REFERENCES public.membership_plan_prices_unfiltered(price_id, plan_id);
REVOKE INSERT, UPDATE ON public.membership_plan_prices_unfiltered FROM authenticated;
CREATE TABLE public.membership_plans_unfiltered (plan_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, plan_name character varying NOT NULL, plan_type character varying NOT NULL, class_count integer, duration_amount integer, duration_unit character varying, is_public boolean DEFAULT true NOT NULL, is_deleted boolean DEFAULT false NOT NULL, stripe_product_id character varying, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT fk_plan_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_duration_unit_check CHECK (duration_unit::text = ANY (ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying]::text[]));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_plan_type_check CHECK (plan_type::text = ANY (ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying]::text[]));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT duration_both_or_neither CHECK ((duration_amount IS NULL) = (duration_unit IS NULL));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT duration_required_unless_class_count CHECK (duration_amount IS NOT NULL AND duration_unit IS NOT NULL OR plan_type::text <> 'recurring'::text AND class_count IS NOT NULL);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_class_count_check CHECK (class_count > 0);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_duration_amount_check CHECK (duration_amount > 0);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_pkey PRIMARY KEY (plan_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_plan_id FOREIGN KEY (plan_id) REFERENCES public.membership_plans_unfiltered(plan_id);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT fk_discount_plan FOREIGN KEY (membership_plan_id) REFERENCES public.membership_plans_unfiltered(plan_id);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT fk_plan_price_plan FOREIGN KEY (plan_id) REFERENCES public.membership_plans_unfiltered(plan_id);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_plan_id_gym_id_key UNIQUE (plan_id, gym_id);
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT fk_discount_plan_gym FOREIGN KEY (membership_plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT fk_membership_plan_gym FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id);
ALTER TABLE public.membership_plan_prices_unfiltered ADD CONSTRAINT fk_plan_price_plan_gym FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_plan_name_check CHECK (plan_name::text <> ''::text);
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT recurring_must_be_monthly CHECK (plan_type::text <> 'recurring'::text OR duration_unit::text = 'month'::text AND duration_amount = 1);
REVOKE UPDATE ON public.membership_plans_unfiltered FROM authenticated;
CREATE TABLE public.stripe_webhook_events (event_id character varying NOT NULL, gym_id uuid NOT NULL, event_type character varying NOT NULL, processed_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.stripe_webhook_events ADD CONSTRAINT fk_webhook_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.stripe_webhook_events ADD CONSTRAINT stripe_webhook_events_pkey PRIMARY KEY (event_id);
REVOKE ALL ON public.stripe_webhook_events FROM authenticated;
CREATE TABLE public.user_activities (activity_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, crm_user_id uuid NOT NULL, gym_id uuid NOT NULL, activity_type character varying NOT NULL, activity_info jsonb DEFAULT '{}'::jsonb, "time" timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_activities ADD CONSTRAINT fk_activity_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_activities ADD CONSTRAINT user_activities_pkey PRIMARY KEY (activity_id);
CREATE TABLE public.user_gym_charges (charge_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, invoice_id uuid NOT NULL, gym_id uuid NOT NULL, crm_user_id uuid NOT NULL, kind public.charge_kind NOT NULL, status public.charge_status NOT NULL, amount integer NOT NULL, currency character(3) DEFAULT 'usd'::bpchar NOT NULL, payment_method_type character varying, stripe_charge_id character varying, stripe_refund_id character varying, refunds_charge_id uuid, charge_time timestamp with time zone DEFAULT now() NOT NULL, stripe_event_payload jsonb);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT fk_charge_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT payment_amount_nonneg CHECK (kind <> 'payment'::public.charge_kind OR amount >= 0);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT payment_has_charge_id CHECK (kind <> 'payment'::public.charge_kind OR stripe_charge_id IS NOT NULL OR payment_method_type::text = 'cash'::text);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT payment_has_no_parent CHECK (kind <> 'payment'::public.charge_kind OR refunds_charge_id IS NULL);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT payment_has_no_refund_id CHECK (kind <> 'payment'::public.charge_kind OR stripe_refund_id IS NULL);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT refund_amount_nonpos CHECK (kind <> 'refund'::public.charge_kind OR amount <= 0);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT refund_has_no_charge_id CHECK (kind <> 'refund'::public.charge_kind OR stripe_charge_id IS NULL);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT refund_has_parent CHECK (kind <> 'refund'::public.charge_kind OR refunds_charge_id IS NOT NULL);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT refund_has_refund_id CHECK (kind <> 'refund'::public.charge_kind OR stripe_refund_id IS NOT NULL);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT user_gym_charges_pkey PRIMARY KEY (charge_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT fk_refund_parent FOREIGN KEY (refunds_charge_id) REFERENCES public.user_gym_charges(charge_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT user_gym_charges_stripe_charge_id_key UNIQUE (stripe_charge_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT user_gym_charges_stripe_refund_id_key UNIQUE (stripe_refund_id);
REVOKE INSERT, UPDATE ON public.user_gym_charges FROM authenticated;
CREATE TABLE public.user_gym_invoice_applied_discounts (applied_discount_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, invoice_id uuid NOT NULL, gym_id uuid NOT NULL, discount_id uuid NOT NULL, amount_off integer NOT NULL, stripe_coupon_id character varying);
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT fk_applied_discount_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT fk_applied_discount_discount_gym FOREIGN KEY (discount_id, gym_id) REFERENCES public.gym_discounts_unfiltered(discount_id, gym_id);
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT user_gym_invoice_applied_discounts_amount_off_check CHECK (amount_off >= 0);
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT user_gym_invoice_applied_discounts_pkey PRIMARY KEY (applied_discount_id);
REVOKE INSERT, UPDATE ON public.user_gym_invoice_applied_discounts FROM authenticated;
CREATE TABLE public.user_gym_invoice_line_items (line_item_id character varying NOT NULL, invoice_id uuid NOT NULL, gym_id uuid NOT NULL, item_type public.line_item_type NOT NULL, name character varying NOT NULL, amount integer NOT NULL, stripe_product_id character varying, item_id uuid);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT fk_line_item_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT custom_line_has_no_item_id CHECK (item_type <> 'custom'::public.line_item_type OR item_id IS NULL);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT fk_line_item_membership_gym FOREIGN KEY (item_id, gym_id) REFERENCES public.member_memberships_unfiltered(item_id, gym_id);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT membership_line_has_item_id CHECK (item_type <> 'membership'::public.line_item_type OR item_id IS NOT NULL);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT user_gym_invoice_line_items_amount_check CHECK (amount >= 0);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT user_gym_invoice_line_items_name_check CHECK (name::text <> ''::text);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT user_gym_invoice_line_items_pkey PRIMARY KEY (line_item_id);
REVOKE INSERT, UPDATE ON public.user_gym_invoice_line_items FROM authenticated;
CREATE TABLE public.user_gym_invoices (invoice_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, crm_user_id uuid NOT NULL, status public.invoice_status DEFAULT 'open'::public.invoice_status NOT NULL, total_amount integer NOT NULL, currency character(3) DEFAULT 'usd'::bpchar NOT NULL, stripe_invoice_id character varying, stripe_payment_intent_id character varying, invoice_time timestamp with time zone DEFAULT now() NOT NULL, stripe_event_payload jsonb);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT fk_invoice_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT user_gym_invoices_invoice_id_gym_id_key UNIQUE (invoice_id, gym_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT fk_charge_invoice_gym FOREIGN KEY (invoice_id, gym_id) REFERENCES public.user_gym_invoices(invoice_id, gym_id);
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT fk_applied_discount_invoice_gym FOREIGN KEY (invoice_id, gym_id) REFERENCES public.user_gym_invoices(invoice_id, gym_id);
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT fk_line_item_invoice_gym FOREIGN KEY (invoice_id, gym_id) REFERENCES public.user_gym_invoices(invoice_id, gym_id);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT user_gym_invoices_pkey PRIMARY KEY (invoice_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT fk_charge_invoice FOREIGN KEY (invoice_id) REFERENCES public.user_gym_invoices(invoice_id) ON DELETE CASCADE;
ALTER TABLE public.user_gym_invoice_applied_discounts ADD CONSTRAINT fk_applied_discount_invoice FOREIGN KEY (invoice_id) REFERENCES public.user_gym_invoices(invoice_id) ON DELETE CASCADE;
ALTER TABLE public.user_gym_invoice_line_items ADD CONSTRAINT fk_line_item_invoice FOREIGN KEY (invoice_id) REFERENCES public.user_gym_invoices(invoice_id) ON DELETE CASCADE;
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT user_gym_invoices_stripe_invoice_id_key UNIQUE (stripe_invoice_id);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT user_gym_invoices_stripe_payment_intent_id_key UNIQUE (stripe_payment_intent_id);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT user_gym_invoices_total_amount_check CHECK (total_amount >= 0);
REVOKE INSERT, UPDATE ON public.user_gym_invoices FROM authenticated;
CREATE TABLE public.user_gym_profiles_unfiltered (crm_user_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, user_id uuid, gym_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, last_class timestamp with time zone, first_name character varying NOT NULL, last_name character varying NOT NULL, photo_url character varying, phone character varying, email character varying, address character varying, emergency_contact_name character varying, emergency_contact_phone character varying, emergency_contact_email character varying, points_balance integer DEFAULT 0 NOT NULL, freeze_start_date date, freeze_end_date date, account_linked_to_id uuid, linked_discount_id uuid, stripe_customer_id character varying, stripe_sub_id_month character varying, stripe_payment_method_id character varying, payment_type character varying, card_brand character varying, card_last_four character varying(4), card_exp_month integer, card_exp_year integer, total_monthly_recurring_price integer DEFAULT 0 NOT NULL);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT fk_profile_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT fk_profile_linked_discount FOREIGN KEY (linked_discount_id) REFERENCES public.gym_discounts_unfiltered(discount_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT fk_profile_linked_discount_gym FOREIGN KEY (linked_discount_id, gym_id) REFERENCES public.gym_discounts_unfiltered(discount_id, gym_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT fk_profile_user FOREIGN KEY (user_id) REFERENCES auth.users(id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT freeze_dates_must_be_paired CHECK (freeze_start_date IS NULL AND freeze_end_date IS NULL OR freeze_start_date IS NOT NULL AND freeze_end_date IS NOT NULL);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT linked_account_no_stripe CHECK (account_linked_to_id IS NULL OR stripe_sub_id_month IS NULL AND freeze_start_date IS NULL AND freeze_end_date IS NULL AND payment_type IS NULL AND card_brand IS NULL AND card_last_four IS NULL AND card_exp_month IS NULL AND card_exp_year IS NULL);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_crm_user_id_gym_id_key UNIQUE (crm_user_id, gym_id);
ALTER TABLE public.gym_classes_log ADD CONSTRAINT fk_class_log_profile_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.member_memberships_unfiltered ADD CONSTRAINT fk_membership_profile_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_activities ADD CONSTRAINT fk_activity_profile_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_gym_charges ADD CONSTRAINT fk_charge_user_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_gym_invoices ADD CONSTRAINT fk_invoice_user_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT fk_profile_linked_account_same_gym FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_first_name_check CHECK (first_name::text <> ''::text);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_last_name_check CHECK (last_name::text <> ''::text);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_pkey PRIMARY KEY (crm_user_id);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_points_balance_check CHECK (points_balance >= 0);
ALTER TABLE public.user_gym_profiles_unfiltered ADD CONSTRAINT user_gym_profiles_unfiltered_total_monthly_recurring_pric_check CHECK (total_monthly_recurring_price >= 0);
REVOKE INSERT, UPDATE ON public.user_gym_profiles_unfiltered FROM authenticated;
CREATE TABLE public.user_gym_reward_redemptions (redemption_id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL, gym_id uuid NOT NULL, crm_user_id uuid NOT NULL, reward_id uuid NOT NULL, point_cost integer NOT NULL, redeemed_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT fk_redemption_gym FOREIGN KEY (gym_id) REFERENCES public.gyms_unfiltered(gym_id);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT fk_redemption_reward FOREIGN KEY (reward_id) REFERENCES public.gym_rewards(reward_id);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT fk_redemption_reward_gym FOREIGN KEY (reward_id, gym_id) REFERENCES public.gym_rewards(reward_id, gym_id);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT fk_redemption_user_gym FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles_unfiltered(crm_user_id, gym_id);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT user_gym_reward_redemptions_pkey PRIMARY KEY (redemption_id);
ALTER TABLE public.user_gym_reward_redemptions ADD CONSTRAINT user_gym_reward_redemptions_point_cost_check CHECK (point_cost >= 0);
REVOKE INSERT, UPDATE ON public.user_gym_reward_redemptions FROM authenticated;
CREATE VIEW public.gym_discounts WITH (security_invoker=true) AS SELECT * FROM public.gym_discounts_unfiltered WHERE stripe_coupon_id IS NOT NULL;
REVOKE INSERT, UPDATE ON public.gym_discounts FROM authenticated;
CREATE VIEW public.gyms WITH (security_invoker=true) AS SELECT gym_id,
    gym_name,
    gym_description,
    timezone,
    stripe_account_id,
    stripe_onboarding_status
   FROM public.gyms_unfiltered
  WHERE (stripe_account_id IS NOT NULL);
REVOKE INSERT, UPDATE ON public.gyms FROM authenticated;
CREATE VIEW public.member_memberships WITH (security_invoker=true) AS SELECT * FROM public.member_memberships_unfiltered WHERE stripe_item_id IS NOT NULL;
REVOKE INSERT, UPDATE ON public.member_memberships FROM authenticated;
CREATE VIEW public.member_memberships_status WITH (security_invoker=true) AS SELECT mm.item_id,
    mm.crm_user_id,
    mm.gym_id,
    mm.plan_id,
    mm.price_id,
    mm.start_date,
    mm.end_date,
    mm.cancel_date,
    mm.last_paid_date,
    mm.next_due_date,
    mm.discount_ids,
    mm.stripe_item_id,
    mm.prorate,
    mm.total_price,
    mm.created_at,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
        CASE
            WHEN ((mm.cancel_date IS NOT NULL) AND (mm.cancel_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'cancelled'::text
            WHEN ((mm.end_date IS NOT NULL) AND (mm.end_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'ended'::text
            WHEN ((freeze_owner.freeze_start_date IS NOT NULL) AND (freeze_owner.freeze_end_date IS NOT NULL) AND (freeze_owner.freeze_start_date <= ((now() AT TIME ZONE g.timezone))::date) AND (((now() AT TIME ZONE g.timezone))::date <= freeze_owner.freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM (((public.member_memberships mm
     JOIN public.gyms g ON ((g.gym_id = mm.gym_id)))
     JOIN public.user_gym_profiles_unfiltered ugp ON ((ugp.crm_user_id = mm.crm_user_id)))
     JOIN public.user_gym_profiles_unfiltered freeze_owner ON ((freeze_owner.crm_user_id = COALESCE(ugp.account_linked_to_id, ugp.crm_user_id))));
CREATE VIEW public.membership_plans WITH (security_invoker=true) AS SELECT * FROM public.membership_plans_unfiltered WHERE stripe_product_id IS NOT NULL;
CREATE VIEW public.membership_plan_prices WITH (security_invoker=true) AS SELECT * FROM public.membership_plan_prices_unfiltered WHERE stripe_price_id IS NOT NULL;
CREATE VIEW public.user_gym_profiles WITH (security_invoker=true) AS SELECT * FROM public.user_gym_profiles_unfiltered WHERE stripe_customer_id IS NOT NULL;
REVOKE INSERT, UPDATE ON public.membership_plan_prices FROM authenticated;
REVOKE INSERT, UPDATE ON public.membership_plans FROM authenticated;
REVOKE INSERT, UPDATE ON public.user_gym_profiles FROM authenticated;
CREATE OR REPLACE TRIGGER trg_enforce_linked_discount_sequence_insert_update BEFORE INSERT OR UPDATE OF linked_discount_num ON public.gym_discounts_unfiltered FOR EACH ROW WHEN (new.discount_type::text = 'linked'::text) EXECUTE FUNCTION public.enforce_linked_discount_sequence();
CREATE OR REPLACE TRIGGER trg_check_discount_ids_gym_match BEFORE INSERT OR UPDATE OF discount_ids ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_discount_ids_gym_match();
CREATE OR REPLACE TRIGGER trg_prevent_cancel_date_overwrite BEFORE UPDATE OF cancel_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_cancel_date_overwrite();
CREATE OR REPLACE TRIGGER trg_prevent_plan_id_overwrite BEFORE UPDATE OF plan_id ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_plan_id_overwrite();
CREATE OR REPLACE TRIGGER trg_prevent_stripe_item_id_overwrite BEFORE UPDATE OF stripe_item_id ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_item_id_overwrite();
CREATE OR REPLACE TRIGGER trg_recurring_no_end_date BEFORE INSERT OR UPDATE OF end_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_end_date();
CREATE OR REPLACE TRIGGER trg_recurring_no_overlapping_daterange BEFORE INSERT OR UPDATE OF cancel_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_overlapping_daterange();
CREATE OR REPLACE TRIGGER trg_check_linked_discount_type BEFORE INSERT OR UPDATE OF linked_discount_id ON public.user_gym_profiles_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_linked_discount_type();
CREATE OR REPLACE TRIGGER trg_enforce_linked_account_hierarchy BEFORE INSERT OR UPDATE OF account_linked_to_id ON public.user_gym_profiles_unfiltered FOR EACH ROW EXECUTE FUNCTION public.enforce_linked_account_hierarchy();
CREATE OR REPLACE TRIGGER trg_prevent_stripe_customer_id_overwrite BEFORE UPDATE OF stripe_customer_id ON public.user_gym_profiles_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_customer_id_overwrite();
