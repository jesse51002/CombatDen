drop policy "Gym staff can insert discounts" on "public"."gym_discounts";

drop policy "Gym staff can update discounts" on "public"."gym_discounts";

drop policy "Gym staff can insert plans" on "public"."membership_plans";

drop policy "Gym staff can update plans" on "public"."membership_plans";

revoke update on table "public"."gym_discounts" from "authenticated";

revoke update on table "public"."membership_plans" from "authenticated";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_streak_check";

alter table "public"."gym_class_schedules" drop constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

drop view if exists "public"."member_memberships_status";


  create table "public"."stripe_webhook_events" (
    "event_id" character varying not null,
    "gym_id" uuid not null,
    "event_type" character varying not null,
    "processed_at" timestamp with time zone not null default now()
      );


alter table "public"."stripe_webhook_events" enable row level security;

alter table "public"."gym_classes" add column "end_date" date;

alter table "public"."gym_discounts" add column "stripe_coupon_id" character varying;

alter table "public"."gyms" add column "stripe_account_id" character varying;

alter table "public"."gyms" add column "stripe_onboarding_status" character varying not null default 'not_started'::character varying;

alter table "public"."member_memberships" add column "stripe_subscription_id" character varying;

alter table "public"."membership_plans" add column "stripe_price_id" character varying;

alter table "public"."membership_plans" add column "stripe_product_id" character varying;

alter table "public"."user_gym_profiles" drop column "streak";

alter table "public"."user_gym_profiles" add column "card_brand" character varying;

alter table "public"."user_gym_profiles" add column "card_exp_month" integer;

alter table "public"."user_gym_profiles" add column "card_exp_year" integer;

alter table "public"."user_gym_profiles" add column "card_last_four" character varying(4);

alter table "public"."user_gym_profiles" add column "payment_type" character varying;

alter table "public"."user_gym_profiles" add column "stripe_customer_id" character varying;

alter table "public"."user_gym_profiles" add column "stripe_payment_method_id" character varying;

alter table "public"."user_gym_transactions" add column "stripe_invoice_id" character varying;

alter table "public"."user_gym_transactions" add column "stripe_payment_intent_id" character varying;

CREATE UNIQUE INDEX idx_profiles_stripe_customer ON public.user_gym_profiles USING btree (stripe_customer_id) WHERE (stripe_customer_id IS NOT NULL);

CREATE INDEX idx_transactions_stripe_pi ON public.user_gym_transactions USING btree (stripe_payment_intent_id) WHERE (stripe_payment_intent_id IS NOT NULL);

CREATE INDEX idx_webhook_events_gym ON public.stripe_webhook_events USING btree (gym_id, processed_at DESC);

CREATE UNIQUE INDEX stripe_webhook_events_pkey ON public.stripe_webhook_events USING btree (event_id);

alter table "public"."stripe_webhook_events" add constraint "stripe_webhook_events_pkey" PRIMARY KEY using index "stripe_webhook_events_pkey";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_check" CHECK (((stripe_onboarding_status)::text = ANY ((ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_check";

alter table "public"."stripe_webhook_events" add constraint "fk_webhook_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."stripe_webhook_events" validate constraint "fk_webhook_gym";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['membership'::character varying, 'custom'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

set check_function_bodies = off;

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

create or replace view "public"."member_memberships_status" as  SELECT crm_user_id,
    gym_id,
    plan_id,
    start_date,
    end_date,
    cancel_date,
    freeze_start_date,
    freeze_end_date,
    last_paid_date,
    next_due_date,
    discount_ids,
    stripe_subscription_id,
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

CREATE TRIGGER trg_prevent_stripe_customer_id_overwrite BEFORE UPDATE OF stripe_customer_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_customer_id_overwrite();


