drop policy "Members can view exceptions" on "public"."gym_class_exceptions";

drop policy "Members can view schedules" on "public"."gym_class_schedules";

drop policy "Members can view classes" on "public"."gym_classes";

drop policy "Users and gym staff can view class logs" on "public"."gym_classes_log";

drop policy "Members can view active rewards" on "public"."gym_rewards";

drop policy "Members can view own memberships" on "public"."member_memberships_unfiltered";

drop policy "Members can view plan prices" on "public"."membership_plan_prices_unfiltered";

drop policy "Members can view gym plans" on "public"."membership_plans_unfiltered";

drop policy "Users and gym staff can view activities" on "public"."user_activities";

drop policy "Users and gym staff can view transactions" on "public"."user_gym_transactions";

alter table "public"."gym_class_schedules" drop constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_duration_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_plan_type_check";

drop view if exists "public"."gym_discounts";

drop view if exists "public"."member_memberships_status";

drop view if exists "public"."user_gym_profiles";

drop view if exists "public"."member_memberships";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_duration_check" CHECK (((duration)::text = ANY ((ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_duration_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_check" CHECK (((stripe_onboarding_status)::text = ANY ((ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.enforce_linked_account_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        -- This profile is becoming a child — ensure it is not already a parent
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE account_linked_to_id = NEW.crm_user_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.crm_user_id;
        END IF;

        -- Ensure the target parent is not itself a child
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
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

create or replace view "public"."gym_discounts" as  SELECT discount_id,
    gym_id,
    discount_name,
    discount_type,
    percentage_off,
    dollar_off,
    membership_plan_id,
    linked_discount_num,
    duration,
    duration_in_months,
    is_deleted,
    stripe_coupon_id,
    created_at
   FROM public.gym_discounts_unfiltered
  WHERE (stripe_coupon_id IS NOT NULL);


create or replace view "public"."member_memberships" as  SELECT item_id,
    crm_user_id,
    gym_id,
    plan_id,
    price_id,
    start_date,
    end_date,
    cancel_date,
    last_paid_date,
    next_due_date,
    discount_ids,
    stripe_item_id,
    prorate,
    total_price,
    created_at
   FROM public.member_memberships_unfiltered
  WHERE (stripe_item_id IS NOT NULL);


create or replace view "public"."member_memberships_status" as  SELECT mm.item_id,
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
            WHEN ((mm.cancel_date IS NOT NULL) AND (mm.cancel_date <= CURRENT_DATE)) THEN 'cancelled'::text
            WHEN ((mm.end_date IS NOT NULL) AND (mm.end_date <= CURRENT_DATE)) THEN 'ended'::text
            WHEN ((freeze_owner.freeze_start_date IS NOT NULL) AND (freeze_owner.freeze_end_date IS NOT NULL) AND (freeze_owner.freeze_start_date <= CURRENT_DATE) AND (CURRENT_DATE <= freeze_owner.freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM ((public.member_memberships mm
     JOIN public.user_gym_profiles_unfiltered ugp ON ((ugp.crm_user_id = mm.crm_user_id)))
     JOIN public.user_gym_profiles_unfiltered freeze_owner ON ((freeze_owner.crm_user_id = COALESCE(ugp.account_linked_to_id, ugp.crm_user_id))));


create or replace view "public"."user_gym_profiles" as  SELECT crm_user_id,
    user_id,
    gym_id,
    created_at,
    last_class,
    first_name,
    last_name,
    photo_url,
    phone,
    email,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    points_balance,
    freeze_start_date,
    freeze_end_date,
    account_linked_to_id,
    linked_discount_id,
    stripe_customer_id,
    stripe_sub_id_month,
    stripe_payment_method_id,
    payment_type,
    card_brand,
    card_last_four,
    card_exp_month,
    card_exp_year
   FROM public.user_gym_profiles_unfiltered
  WHERE (stripe_customer_id IS NOT NULL);



  create policy "hide_incomplete_stripe_records"
  on "public"."gym_discounts_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_coupon_id IS NOT NULL));



  create policy "hide_incomplete_stripe_records"
  on "public"."member_memberships_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_item_id IS NOT NULL));



  create policy "hide_incomplete_stripe_records"
  on "public"."membership_plan_prices_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_price_id IS NOT NULL));



  create policy "hide_incomplete_stripe_records"
  on "public"."membership_plans_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_product_id IS NOT NULL));



  create policy "hide_incomplete_stripe_records"
  on "public"."user_gym_profiles_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_customer_id IS NOT NULL));



  create policy "Members can view exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_exceptions.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



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



  create policy "Members can view classes"
  on "public"."gym_classes"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_classes.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Users and gym staff can view class logs"
  on "public"."gym_classes_log"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Members can view active rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (((is_active = true) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_rewards.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));



  create policy "Members can view own memberships"
  on "public"."member_memberships_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = member_memberships_unfiltered.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Members can view plan prices"
  on "public"."membership_plan_prices_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plan_prices_unfiltered.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Members can view gym plans"
  on "public"."membership_plans_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plans_unfiltered.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Users and gym staff can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



