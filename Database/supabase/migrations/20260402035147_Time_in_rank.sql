alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

alter table "public"."user_gym_profiles" add column "classes_in_rank" integer not null default 0;

alter table "public"."user_gym_profiles" add column "rank_promotion_date" date;

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_classes_in_rank_check" CHECK ((classes_in_rank >= 0)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_classes_in_rank_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";


