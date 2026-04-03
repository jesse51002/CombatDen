drop policy "Gym staff can insert memberships" on "public"."member_memberships";

alter table "public"."gyms" drop constraint "gyms_estimated_classes_rank_1_check";

alter table "public"."gyms" drop constraint "gyms_estimated_classes_rank_2_check";

alter table "public"."gyms" drop constraint "gyms_estimated_classes_rank_3_check";

alter table "public"."gyms" drop constraint "gyms_estimated_classes_rank_4_check";

alter table "public"."gyms" drop constraint "gyms_estimated_classes_rank_5_check";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_classes_in_rank_check";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_current_rank_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

alter table "public"."gyms" drop column "estimated_classes_rank_1";

alter table "public"."gyms" drop column "estimated_classes_rank_2";

alter table "public"."gyms" drop column "estimated_classes_rank_3";

alter table "public"."gyms" drop column "estimated_classes_rank_4";

alter table "public"."gyms" drop column "estimated_classes_rank_5";

alter table "public"."gyms" drop column "rank_1_name";

alter table "public"."gyms" drop column "rank_2_name";

alter table "public"."gyms" drop column "rank_3_name";

alter table "public"."gyms" drop column "rank_4_name";

alter table "public"."gyms" drop column "rank_5_name";

alter table "public"."gyms" drop column "rank_enabled";

alter table "public"."gyms" drop column "rank_preset";

alter table "public"."member_memberships" drop column "status";

alter table "public"."member_memberships" add column "cancel_date" date;

alter table "public"."user_gym_profiles" drop column "classes_in_rank";

alter table "public"."user_gym_profiles" drop column "current_rank";

alter table "public"."user_gym_profiles" drop column "rank_promotion_date";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['membership'::character varying, 'custom'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

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
    total_price,
    created_at,
        CASE
            WHEN ((cancel_date IS NOT NULL) AND (cancel_date <= CURRENT_DATE)) THEN 'cancelled'::text
            WHEN ((end_date IS NOT NULL) AND (end_date <= CURRENT_DATE)) THEN 'ended'::text
            WHEN ((freeze_start_date IS NOT NULL) AND (freeze_end_date IS NOT NULL) AND (freeze_start_date <= CURRENT_DATE) AND (CURRENT_DATE <= freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM public.member_memberships;



