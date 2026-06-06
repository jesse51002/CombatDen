create type "public"."theme_mode" as enum ('system', 'light', 'dark');

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_plan_type_check";

drop view if exists "public"."membership_plans";

alter table "public"."gym_employees" add column "theme_preference" public.theme_mode not null default 'system'::public.theme_mode;

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.prevent_plan_type_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.plan_type IS DISTINCT FROM OLD.plan_type THEN
        RAISE EXCEPTION 'plan_type cannot be changed after creation'
            USING CONSTRAINT = 'plan_type_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

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


CREATE TRIGGER trg_prevent_plan_type_overwrite BEFORE UPDATE OF plan_type ON public.membership_plans_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_plan_type_overwrite();


