create extension if not exists "pg_net" with schema "extensions";

create extension if not exists "btree_gist" with schema "public";

drop policy "Gym owners can view own gym history" on "public"."gym_history";

drop policy "Users can update own data" on "public"."gyms";

drop policy "Users can view own data" on "public"."gyms";

drop policy "Users and gym owners can view activities" on "public"."user_activities";

drop policy "Users can insert activities for their gyms" on "public"."user_activities";

drop policy "Users and gym owners can view transactions" on "public"."user_gym_transactions";

drop policy "Users and gym owners can update profiles" on "public"."users_gym_profiles";

drop policy "Users and gym owners can view profiles" on "public"."users_gym_profiles";

revoke insert on table "public"."gyms" from "authenticated";

revoke update on table "public"."gyms" from "authenticated";

revoke insert on table "public"."user_gym_transactions" from "authenticated";

revoke update on table "public"."user_gym_transactions" from "authenticated";

revoke delete on table "public"."users_gym_profiles" from "anon";

revoke insert on table "public"."users_gym_profiles" from "anon";

revoke references on table "public"."users_gym_profiles" from "anon";

revoke select on table "public"."users_gym_profiles" from "anon";

revoke trigger on table "public"."users_gym_profiles" from "anon";

revoke truncate on table "public"."users_gym_profiles" from "anon";

revoke update on table "public"."users_gym_profiles" from "anon";

revoke delete on table "public"."users_gym_profiles" from "authenticated";

revoke insert on table "public"."users_gym_profiles" from "authenticated";

revoke references on table "public"."users_gym_profiles" from "authenticated";

revoke select on table "public"."users_gym_profiles" from "authenticated";

revoke trigger on table "public"."users_gym_profiles" from "authenticated";

revoke truncate on table "public"."users_gym_profiles" from "authenticated";

revoke update on table "public"."users_gym_profiles" from "authenticated";

revoke delete on table "public"."users_gym_profiles" from "service_role";

revoke insert on table "public"."users_gym_profiles" from "service_role";

revoke references on table "public"."users_gym_profiles" from "service_role";

revoke select on table "public"."users_gym_profiles" from "service_role";

revoke trigger on table "public"."users_gym_profiles" from "service_role";

revoke truncate on table "public"."users_gym_profiles" from "service_role";

revoke update on table "public"."users_gym_profiles" from "service_role";

alter table "public"."gym_history" drop constraint "gym_history_gym_id_fkey";

alter table "public"."gyms" drop constraint "gyms_owner_id_fkey";

alter table "public"."user_activities" drop constraint "user_activities_gym_id_fkey";

alter table "public"."user_activities" drop constraint "user_activities_user_id_fkey";

alter table "public"."user_activities" drop constraint "user_gym";

alter table "public"."user_gym_transactions" drop constraint "user_gym";

alter table "public"."user_gym_transactions" drop constraint "user_gym_transactions_gym_id_fkey";

alter table "public"."user_gym_transactions" drop constraint "user_gym_transactions_user_id_fkey";

alter table "public"."users_gym_profiles" drop constraint "users_gym_profiles_gym_id_fkey";

alter table "public"."users_gym_profiles" drop constraint "users_gym_profiles_user_id_fkey";

alter table "public"."users_gym_profiles" drop constraint "users_gym_profiles_pkey";

drop index if exists "public"."users_gym_profiles_pkey";

drop table "public"."users_gym_profiles";


  create table "public"."gym_class_exceptions" (
    "exception_id" uuid not null default extensions.uuid_generate_v4(),
    "schedule_id" uuid not null,
    "gym_id" uuid not null,
    "original_date" date not null,
    "is_cancelled" boolean,
    "new_class_time" time without time zone,
    "new_duration_minutes" integer,
    "new_max_capacity" integer,
    "new_instructor_id" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_class_exceptions" enable row level security;


  create table "public"."gym_class_schedules" (
    "schedule_id" uuid not null default extensions.uuid_generate_v4(),
    "class_id" uuid not null,
    "gym_id" uuid not null,
    "class_time" time without time zone not null,
    "duration_minutes" integer not null,
    "recurring_unit" character varying not null,
    "recurring_interval" integer not null default 1,
    "sun" boolean not null default false,
    "mon" boolean not null default false,
    "tue" boolean not null default false,
    "wed" boolean not null default false,
    "thu" boolean not null default false,
    "fri" boolean not null default false,
    "sat" boolean not null default false,
    "sun_instructor_id" uuid,
    "mon_instructor_id" uuid,
    "tue_instructor_id" uuid,
    "wed_instructor_id" uuid,
    "thu_instructor_id" uuid,
    "fri_instructor_id" uuid,
    "sat_instructor_id" uuid,
    "is_cancelled" boolean not null default false,
    "start_date" date not null,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_class_schedules" enable row level security;


  create table "public"."gym_classes" (
    "class_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "class_name" character varying not null,
    "class_description" character varying,
    "allowed_plan_ids" jsonb,
    "max_capacity" integer,
    "is_active" boolean not null default true,
    "is_deleted" boolean not null default false,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_classes" enable row level security;


  create table "public"."gym_classes_log" (
    "log_id" uuid not null default extensions.uuid_generate_v4(),
    "crm_user_id" uuid not null,
    "gym_id" uuid not null,
    "class_id" uuid not null,
    "plan_id" uuid not null,
    "instructor_id" uuid,
    "time" timestamp with time zone not null default now()
      );


alter table "public"."gym_classes_log" enable row level security;


  create table "public"."gym_discounts" (
    "discount_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "discount_name" character varying not null,
    "discount_type" character varying not null,
    "discount_active" boolean not null default true,
    "percentage_off" double precision,
    "dollar_off" integer,
    "membership_plan_id" uuid,
    "family_discount_num" integer,
    "end_date" date,
    "is_deleted" boolean not null default false,
    "stripe_coupon_id" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_discounts" enable row level security;


  create table "public"."gym_employees" (
    "employee_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid,
    "gym_id" uuid not null,
    "employee_type" character varying not null,
    "first_name" character varying not null,
    "last_name" character varying not null,
    "phone" character varying,
    "email" character varying,
    "employee_pic_url" character varying,
    "employee_public_description" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_employees" enable row level security;


  create table "public"."gym_rewards" (
    "reward_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "title" character varying not null,
    "amount_off" character varying,
    "image_url" character varying,
    "point_cost" integer not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_rewards" enable row level security;


  create table "public"."member_memberships" (
    "crm_user_id" uuid not null,
    "gym_id" uuid not null,
    "plan_id" uuid not null,
    "price_id" uuid not null,
    "start_date" date not null,
    "end_date" date,
    "cancel_date" date,
    "freeze_start_date" date,
    "freeze_end_date" date,
    "last_paid_date" date,
    "next_due_date" date,
    "discount_ids" jsonb,
    "stripe_id" character varying,
    "total_price" integer not null,
    "price_formula" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_memberships" enable row level security;


  create table "public"."membership_plan_prices" (
    "price_id" uuid not null default extensions.uuid_generate_v4(),
    "plan_id" uuid not null,
    "gym_id" uuid not null,
    "stripe_price_id" character varying,
    "price" integer not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."membership_plan_prices" enable row level security;


  create table "public"."membership_plans" (
    "plan_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "plan_name" character varying not null,
    "plan_type" character varying not null,
    "class_count" integer,
    "duration_amount" integer not null,
    "duration_unit" character varying not null,
    "is_public" boolean not null default true,
    "is_deleted" boolean not null default false,
    "stripe_product_id" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."membership_plans" enable row level security;


  create table "public"."stripe_webhook_events" (
    "event_id" character varying not null,
    "gym_id" uuid not null,
    "event_type" character varying not null,
    "processed_at" timestamp with time zone not null default now()
      );


alter table "public"."stripe_webhook_events" enable row level security;


  create table "public"."user_gym_profiles" (
    "crm_user_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid,
    "gym_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "last_class" timestamp with time zone,
    "first_name" character varying not null,
    "last_name" character varying not null,
    "photo_url" character varying,
    "phone" character varying,
    "email" character varying,
    "address" character varying,
    "emergency_contact_name" character varying,
    "emergency_contact_phone" character varying,
    "emergency_contact_email" character varying,
    "points_balance" integer not null default 0,
    "account_linked_to_id" uuid,
    "stripe_customer_id" character varying,
    "stripe_subscription_id" character varying,
    "stripe_payment_method_id" character varying,
    "payment_type" character varying,
    "card_brand" character varying,
    "card_last_four" character varying(4),
    "card_exp_month" integer,
    "card_exp_year" integer
      );


alter table "public"."user_gym_profiles" enable row level security;

alter table "public"."gym_history" alter column "revenue" set data type integer using "revenue"::integer;

alter table "public"."gyms" drop column "owner_id";

alter table "public"."gyms" add column "gym_description" character varying;

alter table "public"."gyms" add column "stripe_account_id" character varying;

alter table "public"."gyms" add column "stripe_onboarding_status" character varying not null default 'not_started'::character varying;

alter table "public"."gyms" alter column "gym_name" set not null;

alter table "public"."user_activities" drop column "user_id";

alter table "public"."user_activities" add column "crm_user_id" uuid not null;

alter table "public"."user_gym_transactions" drop column "user_id";

alter table "public"."user_gym_transactions" add column "crm_user_id" uuid not null;

alter table "public"."user_gym_transactions" add column "stripe_invoice_id" character varying;

alter table "public"."user_gym_transactions" add column "stripe_payment_intent_id" character varying;

alter table "public"."user_gym_transactions" alter column "amount_paid" set data type integer using "amount_paid"::integer;

CREATE UNIQUE INDEX gym_class_exceptions_pkey ON public.gym_class_exceptions USING btree (exception_id);

CREATE UNIQUE INDEX gym_class_exceptions_schedule_id_original_date_key ON public.gym_class_exceptions USING btree (schedule_id, original_date);

select 1; 
-- CREATE INDEX gym_class_schedules_class_id_daterange_excl ON public.gym_class_schedules USING gist (class_id, daterange(start_date, end_date, '[]'::text));

CREATE UNIQUE INDEX gym_class_schedules_pkey ON public.gym_class_schedules USING btree (schedule_id);

CREATE UNIQUE INDEX gym_class_schedules_schedule_id_gym_id_key ON public.gym_class_schedules USING btree (schedule_id, gym_id);

CREATE UNIQUE INDEX gym_classes_class_id_gym_id_key ON public.gym_classes USING btree (class_id, gym_id);

CREATE UNIQUE INDEX gym_classes_log_pkey ON public.gym_classes_log USING btree (log_id);

CREATE UNIQUE INDEX gym_classes_pkey ON public.gym_classes USING btree (class_id);

CREATE UNIQUE INDEX gym_discounts_discount_id_gym_id_key ON public.gym_discounts USING btree (discount_id, gym_id);

CREATE UNIQUE INDEX gym_discounts_gym_id_membership_plan_id_family_discount_num_key ON public.gym_discounts USING btree (gym_id, membership_plan_id, family_discount_num);

CREATE UNIQUE INDEX gym_discounts_pkey ON public.gym_discounts USING btree (discount_id);

CREATE UNIQUE INDEX gym_employees_employee_id_gym_id_key ON public.gym_employees USING btree (employee_id, gym_id);

CREATE UNIQUE INDEX gym_employees_pkey ON public.gym_employees USING btree (employee_id);

CREATE UNIQUE INDEX gym_employees_user_id_gym_id_key ON public.gym_employees USING btree (user_id, gym_id);

CREATE UNIQUE INDEX gym_rewards_pkey ON public.gym_rewards USING btree (reward_id);

CREATE UNIQUE INDEX idx_max_one_active_price_per_plan ON public.membership_plan_prices USING btree (plan_id) WHERE (is_active = true);

CREATE UNIQUE INDEX idx_profiles_stripe_customer ON public.user_gym_profiles USING btree (stripe_customer_id) WHERE (stripe_customer_id IS NOT NULL);

CREATE INDEX idx_transactions_stripe_pi ON public.user_gym_transactions USING btree (stripe_payment_intent_id) WHERE (stripe_payment_intent_id IS NOT NULL);

CREATE INDEX idx_webhook_events_gym ON public.stripe_webhook_events USING btree (gym_id, processed_at DESC);

CREATE UNIQUE INDEX member_memberships_pkey ON public.member_memberships USING btree (crm_user_id, gym_id, plan_id);

CREATE UNIQUE INDEX membership_plan_prices_pkey ON public.membership_plan_prices USING btree (price_id);

CREATE UNIQUE INDEX membership_plan_prices_price_id_plan_id_key ON public.membership_plan_prices USING btree (price_id, plan_id);

CREATE UNIQUE INDEX membership_plans_pkey ON public.membership_plans USING btree (plan_id);

CREATE UNIQUE INDEX membership_plans_plan_id_gym_id_key ON public.membership_plans USING btree (plan_id, gym_id);

CREATE UNIQUE INDEX stripe_webhook_events_pkey ON public.stripe_webhook_events USING btree (event_id);

CREATE UNIQUE INDEX unique_employee_user_gym ON public.gym_employees USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX unique_user_gym ON public.user_gym_profiles USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX user_gym_profiles_crm_user_id_gym_id_key ON public.user_gym_profiles USING btree (crm_user_id, gym_id);

CREATE UNIQUE INDEX user_gym_profiles_pkey ON public.user_gym_profiles USING btree (crm_user_id);

CREATE UNIQUE INDEX user_gym_profiles_user_id_gym_id_key ON public.user_gym_profiles USING btree (user_id, gym_id);

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_pkey" PRIMARY KEY using index "gym_class_exceptions_pkey";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_pkey" PRIMARY KEY using index "gym_class_schedules_pkey";

alter table "public"."gym_classes" add constraint "gym_classes_pkey" PRIMARY KEY using index "gym_classes_pkey";

alter table "public"."gym_classes_log" add constraint "gym_classes_log_pkey" PRIMARY KEY using index "gym_classes_log_pkey";

alter table "public"."gym_discounts" add constraint "gym_discounts_pkey" PRIMARY KEY using index "gym_discounts_pkey";

alter table "public"."gym_employees" add constraint "gym_employees_pkey" PRIMARY KEY using index "gym_employees_pkey";

alter table "public"."gym_rewards" add constraint "gym_rewards_pkey" PRIMARY KEY using index "gym_rewards_pkey";

alter table "public"."member_memberships" add constraint "member_memberships_pkey" PRIMARY KEY using index "member_memberships_pkey";

alter table "public"."membership_plan_prices" add constraint "membership_plan_prices_pkey" PRIMARY KEY using index "membership_plan_prices_pkey";

alter table "public"."membership_plans" add constraint "membership_plans_pkey" PRIMARY KEY using index "membership_plans_pkey";

alter table "public"."stripe_webhook_events" add constraint "stripe_webhook_events_pkey" PRIMARY KEY using index "stripe_webhook_events_pkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_pkey" PRIMARY KEY using index "user_gym_profiles_pkey";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_gym";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_instructor" FOREIGN KEY (new_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_instructor";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_schedule" FOREIGN KEY (schedule_id, gym_id) REFERENCES public.gym_class_schedules(schedule_id, gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_schedule";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_schedule_id" FOREIGN KEY (schedule_id) REFERENCES public.gym_class_schedules(schedule_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_schedule_id";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_new_duration_minutes_check" CHECK ((new_duration_minutes > 0)) not valid;

alter table "public"."gym_class_exceptions" validate constraint "gym_class_exceptions_new_duration_minutes_check";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_new_max_capacity_check" CHECK ((new_max_capacity > 0)) not valid;

alter table "public"."gym_class_exceptions" validate constraint "gym_class_exceptions_new_max_capacity_check";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_schedule_id_original_date_key" UNIQUE using index "gym_class_exceptions_schedule_id_original_date_key";

alter table "public"."gym_class_schedules" add constraint "fk_sched_fri_instructor" FOREIGN KEY (fri_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_fri_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_mon_instructor" FOREIGN KEY (mon_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_mon_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_sat_instructor" FOREIGN KEY (sat_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_sat_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_sun_instructor" FOREIGN KEY (sun_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_sun_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_thu_instructor" FOREIGN KEY (thu_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_thu_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_tue_instructor" FOREIGN KEY (tue_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_tue_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_wed_instructor" FOREIGN KEY (wed_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_wed_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_class";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_class_id";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_gym";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_check" CHECK (((end_date IS NULL) OR (end_date >= start_date))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_check1" CHECK ((((recurring_unit)::text <> 'weekly'::text) OR sun OR mon OR tue OR wed OR thu OR fri OR sat)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_check1";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_class_id_daterange_excl" EXCLUDE USING gist (class_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_duration_minutes_check" CHECK ((duration_minutes > 0)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_duration_minutes_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_interval_check" CHECK ((recurring_interval > 0)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_interval_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_schedule_id_gym_id_key" UNIQUE using index "gym_class_schedules_schedule_id_gym_id_key";

alter table "public"."gym_classes" add constraint "fk_class_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_gym";

alter table "public"."gym_classes" add constraint "gym_classes_class_id_gym_id_key" UNIQUE using index "gym_classes_class_id_gym_id_key";

alter table "public"."gym_classes" add constraint "gym_classes_class_name_check" CHECK (((class_name)::text <> ''::text)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_class_name_check";

alter table "public"."gym_classes" add constraint "gym_classes_max_capacity_check" CHECK ((max_capacity > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_max_capacity_check";

alter table "public"."gym_classes_log" add constraint "fk_class_log_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_class";

alter table "public"."gym_classes_log" add constraint "fk_class_log_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_class_id";

alter table "public"."gym_classes_log" add constraint "fk_class_log_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_gym";

alter table "public"."gym_classes_log" add constraint "fk_class_log_instructor" FOREIGN KEY (instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_instructor";

alter table "public"."gym_classes_log" add constraint "fk_class_log_membership" FOREIGN KEY (crm_user_id, gym_id, plan_id) REFERENCES public.member_memberships(crm_user_id, gym_id, plan_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_membership";

alter table "public"."gym_classes_log" add constraint "fk_class_log_plan_id" FOREIGN KEY (plan_id) REFERENCES public.membership_plans(plan_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_plan_id";

alter table "public"."gym_classes_log" add constraint "fk_class_log_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_profile_gym";

alter table "public"."gym_discounts" add constraint "chk_family_discount_fields" CHECK (((((discount_type)::text = 'family'::text) AND (membership_plan_id IS NOT NULL) AND (family_discount_num IS NOT NULL)) OR (((discount_type)::text <> 'family'::text) AND (membership_plan_id IS NULL) AND (family_discount_num IS NULL)))) not valid;

alter table "public"."gym_discounts" validate constraint "chk_family_discount_fields";

alter table "public"."gym_discounts" add constraint "fk_discount_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_discounts" validate constraint "fk_discount_gym";

alter table "public"."gym_discounts" add constraint "fk_discount_plan" FOREIGN KEY (membership_plan_id) REFERENCES public.membership_plans(plan_id) not valid;

alter table "public"."gym_discounts" validate constraint "fk_discount_plan";

alter table "public"."gym_discounts" add constraint "fk_discount_plan_gym" FOREIGN KEY (membership_plan_id, gym_id) REFERENCES public.membership_plans(plan_id, gym_id) not valid;

alter table "public"."gym_discounts" validate constraint "fk_discount_plan_gym";

alter table "public"."gym_discounts" add constraint "gym_discounts_check" CHECK ((num_nonnulls(percentage_off, dollar_off) = 1)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_id_gym_id_key" UNIQUE using index "gym_discounts_discount_id_gym_id_key";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_name_check" CHECK (((discount_name)::text <> ''::text)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_name_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'family'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_dollar_off_check" CHECK ((dollar_off > 0)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_dollar_off_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_family_discount_num_check" CHECK ((family_discount_num > 0)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_family_discount_num_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_gym_id_membership_plan_id_family_discount_num_key" UNIQUE using index "gym_discounts_gym_id_membership_plan_id_family_discount_num_key";

alter table "public"."gym_discounts" add constraint "gym_discounts_percentage_off_check" CHECK (((percentage_off > (0)::double precision) AND (percentage_off <= (100)::double precision))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_percentage_off_check";

alter table "public"."gym_employees" add constraint "fk_employee_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_gym";

alter table "public"."gym_employees" add constraint "fk_employee_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_user";

alter table "public"."gym_employees" add constraint "gym_employees_employee_id_gym_id_key" UNIQUE using index "gym_employees_employee_id_gym_id_key";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_first_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_last_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_user_id_gym_id_key" UNIQUE using index "gym_employees_user_id_gym_id_key";

alter table "public"."gym_history" add constraint "fk_history_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_history" validate constraint "fk_history_gym";

alter table "public"."gym_history" add constraint "gym_history_members_churned_check" CHECK ((members_churned >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_churned_check";

alter table "public"."gym_history" add constraint "gym_history_members_gained_check" CHECK ((members_gained >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_gained_check";

alter table "public"."gym_history" add constraint "gym_history_members_retained_check" CHECK ((members_retained >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_retained_check";

alter table "public"."gym_history" add constraint "gym_history_members_total_check" CHECK ((members_total >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_total_check";

alter table "public"."gym_history" add constraint "gym_history_revenue_check" CHECK ((revenue >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_revenue_check";

alter table "public"."gym_rewards" add constraint "fk_reward_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_rewards" validate constraint "fk_reward_gym";

alter table "public"."gym_rewards" add constraint "gym_rewards_point_cost_check" CHECK ((point_cost > 0)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_point_cost_check";

alter table "public"."gym_rewards" add constraint "gym_rewards_title_check" CHECK (((title)::text <> ''::text)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_title_check";

alter table "public"."gyms" add constraint "gyms_gym_name_check" CHECK (((gym_name)::text <> ''::text)) not valid;

alter table "public"."gyms" validate constraint "gyms_gym_name_check";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_check" CHECK (((stripe_onboarding_status)::text = ANY ((ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_check";

alter table "public"."member_memberships" add constraint "fk_membership_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_gym";

alter table "public"."member_memberships" add constraint "fk_membership_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans(plan_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_plan_gym";

alter table "public"."member_memberships" add constraint "fk_membership_price" FOREIGN KEY (price_id) REFERENCES public.membership_plan_prices(price_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_price";

alter table "public"."member_memberships" add constraint "fk_membership_price_plan" FOREIGN KEY (price_id, plan_id) REFERENCES public.membership_plan_prices(price_id, plan_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_price_plan";

alter table "public"."member_memberships" add constraint "fk_membership_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_profile_gym";

alter table "public"."member_memberships" add constraint "member_memberships_total_price_check" CHECK ((total_price >= 0)) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_total_price_check";

alter table "public"."membership_plan_prices" add constraint "fk_plan_price_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plan_prices" validate constraint "fk_plan_price_gym";

alter table "public"."membership_plan_prices" add constraint "fk_plan_price_plan" FOREIGN KEY (plan_id) REFERENCES public.membership_plans(plan_id) not valid;

alter table "public"."membership_plan_prices" validate constraint "fk_plan_price_plan";

alter table "public"."membership_plan_prices" add constraint "fk_plan_price_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans(plan_id, gym_id) not valid;

alter table "public"."membership_plan_prices" validate constraint "fk_plan_price_plan_gym";

alter table "public"."membership_plan_prices" add constraint "membership_plan_prices_price_check" CHECK ((price >= 0)) not valid;

alter table "public"."membership_plan_prices" validate constraint "membership_plan_prices_price_check";

alter table "public"."membership_plan_prices" add constraint "membership_plan_prices_price_id_plan_id_key" UNIQUE using index "membership_plan_prices_price_id_plan_id_key";

alter table "public"."membership_plans" add constraint "fk_plan_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plans" validate constraint "fk_plan_gym";

alter table "public"."membership_plans" add constraint "membership_plans_class_count_check" CHECK ((class_count > 0)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_class_count_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_amount_check" CHECK ((duration_amount > 0)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_amount_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_id_gym_id_key" UNIQUE using index "membership_plans_plan_id_gym_id_key";

alter table "public"."membership_plans" add constraint "membership_plans_plan_name_check" CHECK (((plan_name)::text <> ''::text)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_name_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

alter table "public"."stripe_webhook_events" add constraint "fk_webhook_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."stripe_webhook_events" validate constraint "fk_webhook_gym";

alter table "public"."user_activities" add constraint "fk_activity_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_activities" validate constraint "fk_activity_gym";

alter table "public"."user_activities" add constraint "fk_activity_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_activities" validate constraint "fk_activity_profile_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_linked_account_same_gym" FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_linked_account_same_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_user";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_crm_user_id_gym_id_key" UNIQUE using index "user_gym_profiles_crm_user_id_gym_id_key";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_first_name_check";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_last_name_check";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_points_balance_check" CHECK ((points_balance >= 0)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_points_balance_check";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_user_id_gym_id_key" UNIQUE using index "user_gym_profiles_user_id_gym_id_key";

alter table "public"."user_gym_transactions" add constraint "fk_transaction_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "fk_transaction_gym";

alter table "public"."user_gym_transactions" add constraint "fk_transaction_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "fk_transaction_profile_gym";

alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_amount_paid_check" CHECK ((amount_paid >= 0)) not valid;

alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_amount_paid_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_class_plan_ids_gym_match()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    plan_id_text TEXT;
    plan_uuid UUID;
BEGIN
    IF NEW.allowed_plan_ids IS NOT NULL AND jsonb_array_length(NEW.allowed_plan_ids) > 0 THEN
        FOR plan_id_text IN SELECT jsonb_array_elements_text(NEW.allowed_plan_ids)
        LOOP
            plan_uuid := plan_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM membership_plans
                WHERE plan_id = plan_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'plan_id % does not belong to gym_id %', plan_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_discount_ids_gym_match()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    discount_id_text TEXT;
    discount_uuid UUID;
BEGIN
    IF NEW.discount_ids IS NOT NULL AND jsonb_array_length(NEW.discount_ids) > 0 THEN
        FOR discount_id_text IN SELECT jsonb_array_elements_text(NEW.discount_ids)
        LOOP
            discount_uuid := discount_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM gym_discounts
                WHERE discount_id = discount_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'discount_id % does not belong to gym_id %', discount_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_no_schedule_gaps()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    target_class_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_class_id := OLD.class_id;
    ELSE
        target_class_id := NEW.class_id;
    END IF;

    -- Skip check if no segments remain for this class
    IF NOT EXISTS (
        SELECT 1 FROM gym_class_schedules WHERE class_id = target_class_id
    ) THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Check for gaps: any segment that ends without another starting the next day
    IF EXISTS (
        SELECT 1
        FROM gym_class_schedules a
        LEFT JOIN gym_class_schedules b
            ON b.class_id = a.class_id
            AND b.start_date = a.end_date + 1
        WHERE a.class_id = target_class_id
            AND a.end_date IS NOT NULL
            AND b.schedule_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Gap detected in schedule for class %', target_class_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.enforce_family_discount_sequence()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    max_num INTEGER;
    total_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COALESCE(MAX(family_discount_num), 0) INTO max_num
        FROM gym_discounts
        WHERE gym_id = NEW.gym_id
          AND membership_plan_id = NEW.membership_plan_id
          AND discount_type = 'family';

        IF NEW.family_discount_num <> max_num + 1 THEN
            RAISE EXCEPTION 'family_discount_num must be % (next sequential), got %',
                max_num + 1, NEW.family_discount_num;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.family_discount_num IS DISTINCT FROM OLD.family_discount_num THEN
            SELECT COUNT(*) INTO total_count
            FROM gym_discounts
            WHERE gym_id = NEW.gym_id
              AND membership_plan_id = NEW.membership_plan_id
              AND discount_type = 'family'
              AND discount_id <> NEW.discount_id;

            IF NEW.family_discount_num < 1 OR NEW.family_discount_num > total_count + 1 THEN
                RAISE EXCEPTION 'family_discount_num out of range [1..%]', total_count + 1;
            END IF;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        SELECT COALESCE(MAX(family_discount_num), 0) INTO max_num
        FROM gym_discounts
        WHERE gym_id = OLD.gym_id
          AND membership_plan_id = OLD.membership_plan_id
          AND discount_type = 'family';

        IF OLD.family_discount_num <> max_num THEN
            RAISE EXCEPTION 'Can only delete the highest family_discount_num (%). Got %',
                max_num, OLD.family_discount_num;
        END IF;
        RETURN OLD;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.enforce_linked_account_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        -- This profile is becoming a child — ensure it is not already a parent
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE account_linked_to_id = NEW.crm_user_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.crm_user_id;
        END IF;

        -- Ensure the target parent is not itself a child
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE crm_user_id = NEW.account_linked_to_id
              AND account_linked_to_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Cannot link to account % — it is already linked to another account',
                NEW.account_linked_to_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.gym_has_owner(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.employee_type = 'owner'
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_gym_admin_or_owner(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
        AND gym_employees.employee_type IN ('owner', 'admin')
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_gym_employee(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
    );
$function$
;

create or replace view "public"."member_memberships_status" as  SELECT crm_user_id,
    gym_id,
    plan_id,
    price_id,
    start_date,
    end_date,
    cancel_date,
    freeze_start_date,
    freeze_end_date,
    last_paid_date,
    next_due_date,
    discount_ids,
    stripe_id,
    total_price,
    price_formula,
    created_at,
        CASE
            WHEN ((cancel_date IS NOT NULL) AND (cancel_date <= CURRENT_DATE)) THEN 'cancelled'::text
            WHEN ((end_date IS NOT NULL) AND (end_date <= CURRENT_DATE)) THEN 'ended'::text
            WHEN ((freeze_start_date IS NOT NULL) AND (freeze_end_date IS NOT NULL) AND (freeze_start_date <= CURRENT_DATE) AND (CURRENT_DATE <= freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM public.member_memberships;


CREATE OR REPLACE FUNCTION public.prevent_stripe_customer_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed once set (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_user_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$function$
;

grant delete on table "public"."gym_class_exceptions" to "anon";

grant insert on table "public"."gym_class_exceptions" to "anon";

grant references on table "public"."gym_class_exceptions" to "anon";

grant select on table "public"."gym_class_exceptions" to "anon";

grant trigger on table "public"."gym_class_exceptions" to "anon";

grant truncate on table "public"."gym_class_exceptions" to "anon";

grant update on table "public"."gym_class_exceptions" to "anon";

grant delete on table "public"."gym_class_exceptions" to "authenticated";

grant insert on table "public"."gym_class_exceptions" to "authenticated";

grant references on table "public"."gym_class_exceptions" to "authenticated";

grant select on table "public"."gym_class_exceptions" to "authenticated";

grant trigger on table "public"."gym_class_exceptions" to "authenticated";

grant truncate on table "public"."gym_class_exceptions" to "authenticated";

grant update on table "public"."gym_class_exceptions" to "authenticated";

grant delete on table "public"."gym_class_exceptions" to "service_role";

grant insert on table "public"."gym_class_exceptions" to "service_role";

grant references on table "public"."gym_class_exceptions" to "service_role";

grant select on table "public"."gym_class_exceptions" to "service_role";

grant trigger on table "public"."gym_class_exceptions" to "service_role";

grant truncate on table "public"."gym_class_exceptions" to "service_role";

grant update on table "public"."gym_class_exceptions" to "service_role";

grant delete on table "public"."gym_class_schedules" to "anon";

grant insert on table "public"."gym_class_schedules" to "anon";

grant references on table "public"."gym_class_schedules" to "anon";

grant select on table "public"."gym_class_schedules" to "anon";

grant trigger on table "public"."gym_class_schedules" to "anon";

grant truncate on table "public"."gym_class_schedules" to "anon";

grant update on table "public"."gym_class_schedules" to "anon";

grant delete on table "public"."gym_class_schedules" to "authenticated";

grant insert on table "public"."gym_class_schedules" to "authenticated";

grant references on table "public"."gym_class_schedules" to "authenticated";

grant select on table "public"."gym_class_schedules" to "authenticated";

grant trigger on table "public"."gym_class_schedules" to "authenticated";

grant truncate on table "public"."gym_class_schedules" to "authenticated";

grant update on table "public"."gym_class_schedules" to "authenticated";

grant delete on table "public"."gym_class_schedules" to "service_role";

grant insert on table "public"."gym_class_schedules" to "service_role";

grant references on table "public"."gym_class_schedules" to "service_role";

grant select on table "public"."gym_class_schedules" to "service_role";

grant trigger on table "public"."gym_class_schedules" to "service_role";

grant truncate on table "public"."gym_class_schedules" to "service_role";

grant update on table "public"."gym_class_schedules" to "service_role";

grant delete on table "public"."gym_classes" to "anon";

grant insert on table "public"."gym_classes" to "anon";

grant references on table "public"."gym_classes" to "anon";

grant select on table "public"."gym_classes" to "anon";

grant trigger on table "public"."gym_classes" to "anon";

grant truncate on table "public"."gym_classes" to "anon";

grant update on table "public"."gym_classes" to "anon";

grant delete on table "public"."gym_classes" to "authenticated";

grant insert on table "public"."gym_classes" to "authenticated";

grant references on table "public"."gym_classes" to "authenticated";

grant select on table "public"."gym_classes" to "authenticated";

grant trigger on table "public"."gym_classes" to "authenticated";

grant truncate on table "public"."gym_classes" to "authenticated";

grant update on table "public"."gym_classes" to "authenticated";

grant delete on table "public"."gym_classes" to "service_role";

grant insert on table "public"."gym_classes" to "service_role";

grant references on table "public"."gym_classes" to "service_role";

grant select on table "public"."gym_classes" to "service_role";

grant trigger on table "public"."gym_classes" to "service_role";

grant truncate on table "public"."gym_classes" to "service_role";

grant update on table "public"."gym_classes" to "service_role";

grant delete on table "public"."gym_classes_log" to "anon";

grant insert on table "public"."gym_classes_log" to "anon";

grant references on table "public"."gym_classes_log" to "anon";

grant select on table "public"."gym_classes_log" to "anon";

grant trigger on table "public"."gym_classes_log" to "anon";

grant truncate on table "public"."gym_classes_log" to "anon";

grant update on table "public"."gym_classes_log" to "anon";

grant delete on table "public"."gym_classes_log" to "authenticated";

grant insert on table "public"."gym_classes_log" to "authenticated";

grant references on table "public"."gym_classes_log" to "authenticated";

grant select on table "public"."gym_classes_log" to "authenticated";

grant trigger on table "public"."gym_classes_log" to "authenticated";

grant truncate on table "public"."gym_classes_log" to "authenticated";

grant delete on table "public"."gym_classes_log" to "service_role";

grant insert on table "public"."gym_classes_log" to "service_role";

grant references on table "public"."gym_classes_log" to "service_role";

grant select on table "public"."gym_classes_log" to "service_role";

grant trigger on table "public"."gym_classes_log" to "service_role";

grant truncate on table "public"."gym_classes_log" to "service_role";

grant update on table "public"."gym_classes_log" to "service_role";

grant delete on table "public"."gym_discounts" to "anon";

grant insert on table "public"."gym_discounts" to "anon";

grant references on table "public"."gym_discounts" to "anon";

grant select on table "public"."gym_discounts" to "anon";

grant trigger on table "public"."gym_discounts" to "anon";

grant truncate on table "public"."gym_discounts" to "anon";

grant update on table "public"."gym_discounts" to "anon";

grant delete on table "public"."gym_discounts" to "authenticated";

grant references on table "public"."gym_discounts" to "authenticated";

grant select on table "public"."gym_discounts" to "authenticated";

grant trigger on table "public"."gym_discounts" to "authenticated";

grant truncate on table "public"."gym_discounts" to "authenticated";

grant delete on table "public"."gym_discounts" to "service_role";

grant insert on table "public"."gym_discounts" to "service_role";

grant references on table "public"."gym_discounts" to "service_role";

grant select on table "public"."gym_discounts" to "service_role";

grant trigger on table "public"."gym_discounts" to "service_role";

grant truncate on table "public"."gym_discounts" to "service_role";

grant update on table "public"."gym_discounts" to "service_role";

grant delete on table "public"."gym_employees" to "anon";

grant insert on table "public"."gym_employees" to "anon";

grant references on table "public"."gym_employees" to "anon";

grant select on table "public"."gym_employees" to "anon";

grant trigger on table "public"."gym_employees" to "anon";

grant truncate on table "public"."gym_employees" to "anon";

grant update on table "public"."gym_employees" to "anon";

grant delete on table "public"."gym_employees" to "authenticated";

grant insert on table "public"."gym_employees" to "authenticated";

grant references on table "public"."gym_employees" to "authenticated";

grant select on table "public"."gym_employees" to "authenticated";

grant trigger on table "public"."gym_employees" to "authenticated";

grant truncate on table "public"."gym_employees" to "authenticated";

grant update on table "public"."gym_employees" to "authenticated";

grant delete on table "public"."gym_employees" to "service_role";

grant insert on table "public"."gym_employees" to "service_role";

grant references on table "public"."gym_employees" to "service_role";

grant select on table "public"."gym_employees" to "service_role";

grant trigger on table "public"."gym_employees" to "service_role";

grant truncate on table "public"."gym_employees" to "service_role";

grant update on table "public"."gym_employees" to "service_role";

grant delete on table "public"."gym_rewards" to "anon";

grant insert on table "public"."gym_rewards" to "anon";

grant references on table "public"."gym_rewards" to "anon";

grant select on table "public"."gym_rewards" to "anon";

grant trigger on table "public"."gym_rewards" to "anon";

grant truncate on table "public"."gym_rewards" to "anon";

grant update on table "public"."gym_rewards" to "anon";

grant delete on table "public"."gym_rewards" to "authenticated";

grant insert on table "public"."gym_rewards" to "authenticated";

grant references on table "public"."gym_rewards" to "authenticated";

grant select on table "public"."gym_rewards" to "authenticated";

grant trigger on table "public"."gym_rewards" to "authenticated";

grant truncate on table "public"."gym_rewards" to "authenticated";

grant update on table "public"."gym_rewards" to "authenticated";

grant delete on table "public"."gym_rewards" to "service_role";

grant insert on table "public"."gym_rewards" to "service_role";

grant references on table "public"."gym_rewards" to "service_role";

grant select on table "public"."gym_rewards" to "service_role";

grant trigger on table "public"."gym_rewards" to "service_role";

grant truncate on table "public"."gym_rewards" to "service_role";

grant update on table "public"."gym_rewards" to "service_role";

grant delete on table "public"."member_memberships" to "anon";

grant insert on table "public"."member_memberships" to "anon";

grant references on table "public"."member_memberships" to "anon";

grant select on table "public"."member_memberships" to "anon";

grant trigger on table "public"."member_memberships" to "anon";

grant truncate on table "public"."member_memberships" to "anon";

grant update on table "public"."member_memberships" to "anon";

grant delete on table "public"."member_memberships" to "authenticated";

grant insert on table "public"."member_memberships" to "authenticated";

grant references on table "public"."member_memberships" to "authenticated";

grant select on table "public"."member_memberships" to "authenticated";

grant trigger on table "public"."member_memberships" to "authenticated";

grant truncate on table "public"."member_memberships" to "authenticated";

grant delete on table "public"."member_memberships" to "service_role";

grant insert on table "public"."member_memberships" to "service_role";

grant references on table "public"."member_memberships" to "service_role";

grant select on table "public"."member_memberships" to "service_role";

grant trigger on table "public"."member_memberships" to "service_role";

grant truncate on table "public"."member_memberships" to "service_role";

grant update on table "public"."member_memberships" to "service_role";

grant delete on table "public"."membership_plan_prices" to "anon";

grant insert on table "public"."membership_plan_prices" to "anon";

grant references on table "public"."membership_plan_prices" to "anon";

grant select on table "public"."membership_plan_prices" to "anon";

grant trigger on table "public"."membership_plan_prices" to "anon";

grant truncate on table "public"."membership_plan_prices" to "anon";

grant update on table "public"."membership_plan_prices" to "anon";

grant delete on table "public"."membership_plan_prices" to "authenticated";

grant references on table "public"."membership_plan_prices" to "authenticated";

grant select on table "public"."membership_plan_prices" to "authenticated";

grant trigger on table "public"."membership_plan_prices" to "authenticated";

grant truncate on table "public"."membership_plan_prices" to "authenticated";

grant delete on table "public"."membership_plan_prices" to "service_role";

grant insert on table "public"."membership_plan_prices" to "service_role";

grant references on table "public"."membership_plan_prices" to "service_role";

grant select on table "public"."membership_plan_prices" to "service_role";

grant trigger on table "public"."membership_plan_prices" to "service_role";

grant truncate on table "public"."membership_plan_prices" to "service_role";

grant update on table "public"."membership_plan_prices" to "service_role";

grant delete on table "public"."membership_plans" to "anon";

grant insert on table "public"."membership_plans" to "anon";

grant references on table "public"."membership_plans" to "anon";

grant select on table "public"."membership_plans" to "anon";

grant trigger on table "public"."membership_plans" to "anon";

grant truncate on table "public"."membership_plans" to "anon";

grant update on table "public"."membership_plans" to "anon";

grant delete on table "public"."membership_plans" to "authenticated";

grant insert on table "public"."membership_plans" to "authenticated";

grant references on table "public"."membership_plans" to "authenticated";

grant select on table "public"."membership_plans" to "authenticated";

grant trigger on table "public"."membership_plans" to "authenticated";

grant truncate on table "public"."membership_plans" to "authenticated";

grant delete on table "public"."membership_plans" to "service_role";

grant insert on table "public"."membership_plans" to "service_role";

grant references on table "public"."membership_plans" to "service_role";

grant select on table "public"."membership_plans" to "service_role";

grant trigger on table "public"."membership_plans" to "service_role";

grant truncate on table "public"."membership_plans" to "service_role";

grant update on table "public"."membership_plans" to "service_role";

grant delete on table "public"."stripe_webhook_events" to "anon";

grant insert on table "public"."stripe_webhook_events" to "anon";

grant references on table "public"."stripe_webhook_events" to "anon";

grant select on table "public"."stripe_webhook_events" to "anon";

grant trigger on table "public"."stripe_webhook_events" to "anon";

grant truncate on table "public"."stripe_webhook_events" to "anon";

grant update on table "public"."stripe_webhook_events" to "anon";

grant delete on table "public"."stripe_webhook_events" to "service_role";

grant insert on table "public"."stripe_webhook_events" to "service_role";

grant references on table "public"."stripe_webhook_events" to "service_role";

grant select on table "public"."stripe_webhook_events" to "service_role";

grant trigger on table "public"."stripe_webhook_events" to "service_role";

grant truncate on table "public"."stripe_webhook_events" to "service_role";

grant update on table "public"."stripe_webhook_events" to "service_role";

grant delete on table "public"."user_gym_profiles" to "anon";

grant insert on table "public"."user_gym_profiles" to "anon";

grant references on table "public"."user_gym_profiles" to "anon";

grant select on table "public"."user_gym_profiles" to "anon";

grant trigger on table "public"."user_gym_profiles" to "anon";

grant truncate on table "public"."user_gym_profiles" to "anon";

grant update on table "public"."user_gym_profiles" to "anon";

grant delete on table "public"."user_gym_profiles" to "authenticated";

grant references on table "public"."user_gym_profiles" to "authenticated";

grant select on table "public"."user_gym_profiles" to "authenticated";

grant trigger on table "public"."user_gym_profiles" to "authenticated";

grant truncate on table "public"."user_gym_profiles" to "authenticated";

grant delete on table "public"."user_gym_profiles" to "service_role";

grant insert on table "public"."user_gym_profiles" to "service_role";

grant references on table "public"."user_gym_profiles" to "service_role";

grant select on table "public"."user_gym_profiles" to "service_role";

grant trigger on table "public"."user_gym_profiles" to "service_role";

grant truncate on table "public"."user_gym_profiles" to "service_role";

grant update on table "public"."user_gym_profiles" to "service_role";


  create policy "Gym employees can view exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_exceptions.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym employees can view schedules"
  on "public"."gym_class_schedules"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert schedules"
  on "public"."gym_class_schedules"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update schedules"
  on "public"."gym_class_schedules"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view schedules"
  on "public"."gym_class_schedules"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.gym_classes
  WHERE ((gym_classes.class_id = gym_class_schedules.class_id) AND (gym_classes.is_active = true)))) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_schedules.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));



  create policy "Gym employees can view classes"
  on "public"."gym_classes"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert classes"
  on "public"."gym_classes"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update classes"
  on "public"."gym_classes"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view classes"
  on "public"."gym_classes"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_classes.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym staff can insert class logs"
  on "public"."gym_classes_log"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view class logs"
  on "public"."gym_classes_log"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can view discounts"
  on "public"."gym_discounts"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Employees can view gym staff"
  on "public"."gym_employees"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Owners and admins can insert employees"
  on "public"."gym_employees"
  as permissive
  for insert
  to authenticated
with check ((public.is_gym_admin_or_owner(gym_id) OR (((employee_type)::text = 'owner'::text) AND (user_id = auth.uid()) AND (NOT public.gym_has_owner(gym_id)))));



  create policy "Owners and admins can update employees"
  on "public"."gym_employees"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view own gym history"
  on "public"."gym_history"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert rewards"
  on "public"."gym_rewards"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update rewards"
  on "public"."gym_rewards"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view active rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (((is_active = true) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_rewards.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));



  create policy "Gym staff can view own gym"
  on "public"."gyms"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view own memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = member_memberships.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym staff can view plan prices"
  on "public"."membership_plan_prices"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view plan prices"
  on "public"."membership_plan_prices"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plan_prices.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym staff can view plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view gym plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plans.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym staff can insert activities"
  on "public"."user_activities"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view profiles"
  on "public"."user_gym_profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));


CREATE TRIGGER trg_enforce_no_schedule_gaps AFTER INSERT OR DELETE OR UPDATE ON public.gym_class_schedules FOR EACH ROW EXECUTE FUNCTION public.check_no_schedule_gaps();

CREATE TRIGGER trg_check_class_plan_ids_gym_match BEFORE INSERT OR UPDATE OF allowed_plan_ids ON public.gym_classes FOR EACH ROW EXECUTE FUNCTION public.check_class_plan_ids_gym_match();

CREATE TRIGGER trg_enforce_family_discount_sequence_delete BEFORE DELETE ON public.gym_discounts FOR EACH ROW WHEN (((old.discount_type)::text = 'family'::text)) EXECUTE FUNCTION public.enforce_family_discount_sequence();

CREATE TRIGGER trg_enforce_family_discount_sequence_insert_update BEFORE INSERT OR UPDATE OF family_discount_num ON public.gym_discounts FOR EACH ROW WHEN (((new.discount_type)::text = 'family'::text)) EXECUTE FUNCTION public.enforce_family_discount_sequence();

CREATE TRIGGER trg_check_discount_ids_gym_match BEFORE INSERT OR UPDATE OF discount_ids ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_discount_ids_gym_match();

CREATE TRIGGER trg_enforce_linked_account_hierarchy BEFORE INSERT OR UPDATE OF account_linked_to_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.enforce_linked_account_hierarchy();

CREATE TRIGGER trg_prevent_stripe_customer_id_overwrite BEFORE UPDATE OF stripe_customer_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_customer_id_overwrite();

CREATE TRIGGER trg_prevent_user_id_overwrite BEFORE UPDATE OF user_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_overwrite();


