drop policy "Users can insert activities for their gyms" on "public"."user_activities";

drop policy "Users and gym owners can view activities" on "public"."user_activities";

drop policy "Users and gym owners can view transactions" on "public"."user_gym_transactions";

alter table "public"."user_activities" drop constraint "user_activities_user_id_fkey";

alter table "public"."user_activities" drop constraint "user_gym";

alter table "public"."user_gym_transactions" drop constraint "user_gym";

alter table "public"."user_gym_transactions" drop constraint "user_gym_transactions_user_id_fkey";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_pkey";

drop index if exists "public"."user_gym_profiles_pkey";


  create table "public"."gym_discounts" (
    "discount_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "discount_name" character varying not null,
    "percentage_off" double precision,
    "dollar_off" double precision,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_discounts" enable row level security;


  create table "public"."gym_rewards" (
    "reward_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "title" character varying not null,
    "subtitle" character varying,
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
    "start_date" date not null,
    "status" character varying not null default 'active'::character varying,
    "last_paid_date" date,
    "next_due_date" date,
    "discount_ids" jsonb,
    "custom_discounts" jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_memberships" enable row level security;


  create table "public"."membership_plans" (
    "plan_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "plan_name" character varying not null,
    "plan_type" character varying,
    "base_cost" double precision not null,
    "additional_member_costs" jsonb,
    "billing_cycle" character varying not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."membership_plans" enable row level security;

alter table "public"."gyms" add column "estimated_classes_rank_1" integer not null;

alter table "public"."gyms" add column "estimated_classes_rank_2" integer not null;

alter table "public"."gyms" add column "estimated_classes_rank_3" integer not null;

alter table "public"."gyms" add column "estimated_classes_rank_4" integer not null;

alter table "public"."gyms" add column "estimated_classes_rank_5" integer not null;

alter table "public"."gyms" add column "rank_1_name" character varying;

alter table "public"."gyms" add column "rank_2_name" character varying;

alter table "public"."gyms" add column "rank_3_name" character varying;

alter table "public"."gyms" add column "rank_4_name" character varying;

alter table "public"."gyms" add column "rank_5_name" character varying;

alter table "public"."gyms" add column "rank_enabled" boolean not null default true;

alter table "public"."gyms" add column "rank_preset" character varying;

alter table "public"."user_activities" drop column "user_id";

alter table "public"."user_activities" add column "crm_user_id" uuid not null;

alter table "public"."user_gym_profiles" drop column "rank";

alter table "public"."user_gym_profiles" add column "account_linked_to_id" uuid;

alter table "public"."user_gym_profiles" add column "address" character varying;

alter table "public"."user_gym_profiles" add column "crm_user_id" uuid not null default extensions.uuid_generate_v4();

alter table "public"."user_gym_profiles" add column "current_rank" integer;

alter table "public"."user_gym_profiles" add column "email" character varying;

alter table "public"."user_gym_profiles" add column "emergency_contact_email" character varying;

alter table "public"."user_gym_profiles" add column "emergency_contact_name" character varying;

alter table "public"."user_gym_profiles" add column "emergency_contact_phone" character varying;

alter table "public"."user_gym_profiles" add column "phone" character varying;

alter table "public"."user_gym_profiles" add column "photo_url" character varying;

alter table "public"."user_gym_profiles" add column "points_balance" integer not null default 0;

alter table "public"."user_gym_profiles" alter column "user_id" drop not null;

alter table "public"."user_gym_transactions" drop column "user_id";

alter table "public"."user_gym_transactions" add column "crm_user_id" uuid not null;

CREATE UNIQUE INDEX gym_discounts_pkey ON public.gym_discounts USING btree (discount_id);

CREATE UNIQUE INDEX gym_rewards_pkey ON public.gym_rewards USING btree (reward_id);

CREATE UNIQUE INDEX member_memberships_pkey ON public.member_memberships USING btree (crm_user_id, gym_id, plan_id);

CREATE UNIQUE INDEX membership_plans_pkey ON public.membership_plans USING btree (plan_id);

CREATE UNIQUE INDEX membership_plans_plan_id_gym_id_key ON public.membership_plans USING btree (plan_id, gym_id);

CREATE UNIQUE INDEX unique_user_gym ON public.user_gym_profiles USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX user_gym_profiles_crm_user_id_gym_id_key ON public.user_gym_profiles USING btree (crm_user_id, gym_id);

CREATE UNIQUE INDEX user_gym_profiles_pkey ON public.user_gym_profiles USING btree (crm_user_id);

alter table "public"."gym_discounts" add constraint "gym_discounts_pkey" PRIMARY KEY using index "gym_discounts_pkey";

alter table "public"."gym_rewards" add constraint "gym_rewards_pkey" PRIMARY KEY using index "gym_rewards_pkey";

alter table "public"."member_memberships" add constraint "member_memberships_pkey" PRIMARY KEY using index "member_memberships_pkey";

alter table "public"."membership_plans" add constraint "membership_plans_pkey" PRIMARY KEY using index "membership_plans_pkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_pkey" PRIMARY KEY using index "user_gym_profiles_pkey";

alter table "public"."gym_discounts" add constraint "gym_discounts_check" CHECK ((num_nonnulls(percentage_off, dollar_off) = 1)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_name_check" CHECK (((discount_name)::text <> ''::text)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_name_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_dollar_off_check" CHECK ((dollar_off > (0)::double precision)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_dollar_off_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_gym_id_fkey";

alter table "public"."gym_discounts" add constraint "gym_discounts_percentage_off_check" CHECK (((percentage_off > (0)::double precision) AND (percentage_off <= (100)::double precision))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_percentage_off_check";

alter table "public"."gym_history" add constraint "gym_history_members_churned_check" CHECK ((members_churned >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_churned_check";

alter table "public"."gym_history" add constraint "gym_history_members_gained_check" CHECK ((members_gained >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_gained_check";

alter table "public"."gym_history" add constraint "gym_history_members_retained_check" CHECK ((members_retained >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_retained_check";

alter table "public"."gym_history" add constraint "gym_history_members_total_check" CHECK ((members_total >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_members_total_check";

alter table "public"."gym_history" add constraint "gym_history_revenue_check" CHECK ((revenue >= (0)::double precision)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_revenue_check";

alter table "public"."gym_rewards" add constraint "gym_rewards_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_gym_id_fkey";

alter table "public"."gym_rewards" add constraint "gym_rewards_point_cost_check" CHECK ((point_cost > 0)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_point_cost_check";

alter table "public"."gym_rewards" add constraint "gym_rewards_title_check" CHECK (((title)::text <> ''::text)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_title_check";

alter table "public"."gyms" add constraint "gyms_estimated_classes_rank_1_check" CHECK ((estimated_classes_rank_1 >= 0)) not valid;

alter table "public"."gyms" validate constraint "gyms_estimated_classes_rank_1_check";

alter table "public"."gyms" add constraint "gyms_estimated_classes_rank_2_check" CHECK ((estimated_classes_rank_2 >= 0)) not valid;

alter table "public"."gyms" validate constraint "gyms_estimated_classes_rank_2_check";

alter table "public"."gyms" add constraint "gyms_estimated_classes_rank_3_check" CHECK ((estimated_classes_rank_3 >= 0)) not valid;

alter table "public"."gyms" validate constraint "gyms_estimated_classes_rank_3_check";

alter table "public"."gyms" add constraint "gyms_estimated_classes_rank_4_check" CHECK ((estimated_classes_rank_4 >= 0)) not valid;

alter table "public"."gyms" validate constraint "gyms_estimated_classes_rank_4_check";

alter table "public"."gyms" add constraint "gyms_estimated_classes_rank_5_check" CHECK ((estimated_classes_rank_5 >= 0)) not valid;

alter table "public"."gyms" validate constraint "gyms_estimated_classes_rank_5_check";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_crm_user_id_gym_id_fkey" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_crm_user_id_gym_id_fkey";

alter table "public"."member_memberships" add constraint "member_memberships_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_gym_id_fkey";

alter table "public"."member_memberships" add constraint "member_memberships_plan_id_gym_id_fkey" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans(plan_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_plan_id_gym_id_fkey";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";

alter table "public"."membership_plans" add constraint "membership_plans_base_cost_check" CHECK ((base_cost >= (0)::double precision)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_base_cost_check";

alter table "public"."membership_plans" add constraint "membership_plans_billing_cycle_check" CHECK (((billing_cycle)::text <> ''::text)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_billing_cycle_check";

alter table "public"."membership_plans" add constraint "membership_plans_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_gym_id_fkey";

alter table "public"."membership_plans" add constraint "membership_plans_plan_id_gym_id_key" UNIQUE using index "membership_plans_plan_id_gym_id_key";

alter table "public"."membership_plans" add constraint "membership_plans_plan_name_check" CHECK (((plan_name)::text <> ''::text)) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_name_check";

alter table "public"."user_activities" add constraint "user_activities_crm_user_id_gym_id_fkey" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_activities" validate constraint "user_activities_crm_user_id_gym_id_fkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_account_linked_to_id_gym_id_fkey" FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_account_linked_to_id_gym_id_fkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_crm_user_id_gym_id_key" UNIQUE using index "user_gym_profiles_crm_user_id_gym_id_key";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_current_rank_check" CHECK (((current_rank IS NULL) OR ((current_rank >= 1) AND (current_rank <= 5)))) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_current_rank_check";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_points_balance_check" CHECK ((points_balance >= 0)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_points_balance_check";

alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_crm_user_id_gym_id_fkey" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_crm_user_id_gym_id_fkey";

set check_function_bodies = off;

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

grant delete on table "public"."gym_discounts" to "anon";

grant insert on table "public"."gym_discounts" to "anon";

grant references on table "public"."gym_discounts" to "anon";

grant select on table "public"."gym_discounts" to "anon";

grant trigger on table "public"."gym_discounts" to "anon";

grant truncate on table "public"."gym_discounts" to "anon";

grant update on table "public"."gym_discounts" to "anon";

grant delete on table "public"."gym_discounts" to "authenticated";

grant insert on table "public"."gym_discounts" to "authenticated";

grant references on table "public"."gym_discounts" to "authenticated";

grant select on table "public"."gym_discounts" to "authenticated";

grant trigger on table "public"."gym_discounts" to "authenticated";

grant truncate on table "public"."gym_discounts" to "authenticated";

grant update on table "public"."gym_discounts" to "authenticated";

grant delete on table "public"."gym_discounts" to "service_role";

grant insert on table "public"."gym_discounts" to "service_role";

grant references on table "public"."gym_discounts" to "service_role";

grant select on table "public"."gym_discounts" to "service_role";

grant trigger on table "public"."gym_discounts" to "service_role";

grant truncate on table "public"."gym_discounts" to "service_role";

grant update on table "public"."gym_discounts" to "service_role";

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

grant update on table "public"."member_memberships" to "authenticated";

grant delete on table "public"."member_memberships" to "service_role";

grant insert on table "public"."member_memberships" to "service_role";

grant references on table "public"."member_memberships" to "service_role";

grant select on table "public"."member_memberships" to "service_role";

grant trigger on table "public"."member_memberships" to "service_role";

grant truncate on table "public"."member_memberships" to "service_role";

grant update on table "public"."member_memberships" to "service_role";

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

grant update on table "public"."membership_plans" to "authenticated";

grant delete on table "public"."membership_plans" to "service_role";

grant insert on table "public"."membership_plans" to "service_role";

grant references on table "public"."membership_plans" to "service_role";

grant select on table "public"."membership_plans" to "service_role";

grant trigger on table "public"."membership_plans" to "service_role";

grant truncate on table "public"."membership_plans" to "service_role";

grant update on table "public"."membership_plans" to "service_role";


  create policy "Gym owners can insert discounts"
  on "public"."gym_discounts"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_discounts.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can update discounts"
  on "public"."gym_discounts"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_discounts.gym_id) AND (gyms.owner_id = auth.uid())))))
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_discounts.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can view discounts"
  on "public"."gym_discounts"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_discounts.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can insert rewards"
  on "public"."gym_rewards"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_rewards.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can update rewards"
  on "public"."gym_rewards"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_rewards.gym_id) AND (gyms.owner_id = auth.uid())))))
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_rewards.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can view rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_rewards.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Members can view active rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (((is_active = true) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_rewards.gym_id) AND (user_gym_profiles.user_id = auth.uid()))))));



  create policy "Gym owners can insert memberships"
  on "public"."member_memberships"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = member_memberships.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can update memberships"
  on "public"."member_memberships"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = member_memberships.gym_id) AND (gyms.owner_id = auth.uid())))))
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = member_memberships.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can view memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = member_memberships.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Members can view own memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = member_memberships.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym owners can insert plans"
  on "public"."membership_plans"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = membership_plans.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can update plans"
  on "public"."membership_plans"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = membership_plans.gym_id) AND (gyms.owner_id = auth.uid())))))
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = membership_plans.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can view plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = membership_plans.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Members can view gym plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = membership_plans.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym owners can insert activities"
  on "public"."user_activities"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_activities.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Gym owners can insert transactions"
  on "public"."user_gym_transactions"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_transactions.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Users and gym owners can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_activities.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users and gym owners can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_transactions.gym_id) AND (gyms.owner_id = auth.uid()))))));


CREATE TRIGGER trg_check_discount_ids_gym_match BEFORE INSERT OR UPDATE OF discount_ids ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_discount_ids_gym_match();

CREATE TRIGGER trg_prevent_user_id_overwrite BEFORE UPDATE OF user_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_overwrite();


