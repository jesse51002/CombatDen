alter table "public"."membership_plans" drop constraint "membership_plans_billing_cycle_check";

alter table "public"."user_gym_profiles" drop constraint "fk_profile_linked_account_same_gym";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

alter table "public"."member_memberships" add column "account_linked_to_id" uuid;

alter table "public"."member_memberships" add column "freeze_end_date" date;

alter table "public"."member_memberships" add column "freeze_start_date" date;

alter table "public"."member_memberships" add column "total_price" double precision not null;

alter table "public"."membership_plans" drop column "billing_cycle";

alter table "public"."membership_plans" drop column "is_active";

alter table "public"."membership_plans" add column "class_count" integer;

alter table "public"."membership_plans" add column "duration_amount" integer not null;

alter table "public"."membership_plans" add column "duration_unit" character varying not null;

alter table "public"."membership_plans" alter column "plan_type" set not null;

alter table "public"."user_gym_profiles" drop column "account_linked_to_id";

alter table "public"."user_gym_profiles" drop column "account_status";

alter table "public"."member_memberships" add constraint "fk_membership_linked_account_same_gym" FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_linked_account_same_gym";

alter table "public"."member_memberships" add constraint "member_memberships_total_price_check" CHECK ((total_price >= (0)::double precision)) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_total_price_check";

alter table "public"."membership_plans" add constraint "membership_plans_class_count_check" CHECK ((class_count > 0)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_class_count_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_amount_check" CHECK ((duration_amount > 0)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_amount_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";


