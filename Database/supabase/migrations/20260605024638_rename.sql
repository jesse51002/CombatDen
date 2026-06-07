revoke delete on table "public"."gym_discount_values_unfiltered" from "authenticated";

revoke insert on table "public"."gym_discount_values_unfiltered" from "authenticated";

revoke update on table "public"."gym_discount_values_unfiltered" from "authenticated";

revoke delete on table "public"."gym_waiver_versions" from "authenticated";

revoke update on table "public"."gym_waiver_versions" from "authenticated";

revoke insert on table "public"."member_membership_applied_discounts_unfiltered" from "authenticated";

revoke update on table "public"."member_membership_applied_discounts_unfiltered" from "authenticated";

revoke delete on table "public"."member_waiver_signatures" from "authenticated";

revoke update on table "public"."member_waiver_signatures" from "authenticated";

alter table "public"."membership_plans_unfiltered" drop constraint "chk_plan_linked_prices_array";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_plan_type_check";

drop view if exists "public"."membership_plans";

alter table "public"."membership_plans_unfiltered" drop column "linked_discount_prices";

alter table "public"."membership_plans_unfiltered" add column "linked_discount_ids" jsonb not null default '[]'::jsonb;

alter table "public"."membership_plans_unfiltered" add constraint "chk_plan_linked_ids_array" CHECK ((jsonb_typeof(linked_discount_ids) = 'array'::text)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "chk_plan_linked_ids_array";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

create or replace view "public"."membership_plans" as  SELECT plan_id,
    gym_id,
    plan_name,
    plan_type,
    class_count,
    duration_amount,
    duration_unit,
    is_public,
    is_deleted,
    stripe_product_id,
    waiver_ids,
    linked_discount_enabled,
    linked_discount_ids,
    created_at
   FROM public.membership_plans_unfiltered
  WHERE (stripe_product_id IS NOT NULL);



