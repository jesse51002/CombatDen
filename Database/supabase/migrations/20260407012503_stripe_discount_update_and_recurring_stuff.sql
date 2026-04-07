revoke update on table "public"."gym_classes_log" from "authenticated";

revoke insert on table "public"."gym_discounts" from "authenticated";

revoke update on table "public"."gym_discounts" from "authenticated";

revoke update on table "public"."member_memberships" from "authenticated";

revoke insert on table "public"."membership_plan_prices" from "authenticated";

revoke update on table "public"."membership_plan_prices" from "authenticated";

revoke update on table "public"."membership_plans" from "authenticated";

revoke delete on table "public"."stripe_webhook_events" from "authenticated";

revoke insert on table "public"."stripe_webhook_events" from "authenticated";

revoke references on table "public"."stripe_webhook_events" from "authenticated";

revoke select on table "public"."stripe_webhook_events" from "authenticated";

revoke trigger on table "public"."stripe_webhook_events" from "authenticated";

revoke truncate on table "public"."stripe_webhook_events" from "authenticated";

revoke update on table "public"."stripe_webhook_events" from "authenticated";

revoke insert on table "public"."user_gym_profiles" from "authenticated";

revoke update on table "public"."user_gym_profiles" from "authenticated";

alter table "public"."gym_class_schedules" drop constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

alter table "public"."gym_discounts" drop column "end_date";

alter table "public"."gym_discounts" add column "duration" character varying not null;

alter table "public"."gym_discounts" add column "duration_in_months" integer;

alter table "public"."user_gym_profiles" drop column "stripe_subscription_id";

alter table "public"."user_gym_profiles" add column "stripe_sub_id_month" character varying;

alter table "public"."user_gym_profiles" add column "stripe_sub_id_week" character varying;

alter table "public"."user_gym_profiles" add column "stripe_sub_id_year" character varying;

alter table "public"."gym_discounts" add constraint "chk_duration_in_months" CHECK (((((duration)::text = 'repeating'::text) AND (duration_in_months IS NOT NULL)) OR (((duration)::text <> 'repeating'::text) AND (duration_in_months IS NULL)))) not valid;

alter table "public"."gym_discounts" validate constraint "chk_duration_in_months";

alter table "public"."gym_discounts" add constraint "gym_discounts_duration_check" CHECK (((duration)::text = ANY ((ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_duration_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_duration_in_months_check" CHECK ((duration_in_months > 0)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_duration_in_months_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'family'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_check" CHECK (((stripe_onboarding_status)::text = ANY ((ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";


