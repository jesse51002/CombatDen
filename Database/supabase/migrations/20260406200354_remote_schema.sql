drop extension if exists "pg_net";

DROP TABLE IF EXISTS "public"."gym_class_exceptions" CASCADE;
DROP TABLE IF EXISTS "public"."gym_class_schedules" CASCADE;
DROP TABLE IF EXISTS "public"."gym_classes" CASCADE;
DROP TABLE IF EXISTS "public"."gym_classes_log" CASCADE;
DROP TABLE IF EXISTS "public"."gym_discounts" CASCADE;
DROP TABLE IF EXISTS "public"."gym_employees" CASCADE;
DROP TABLE IF EXISTS "public"."gym_rewards" CASCADE;
DROP TABLE IF EXISTS "public"."member_memberships" CASCADE;
DROP TABLE IF EXISTS "public"."membership_plans" CASCADE;
DROP TABLE IF EXISTS "public"."stripe_webhook_events" CASCADE;
DROP TABLE IF EXISTS "public"."user_gym_profiles" CASCADE;


drop policy if exists "Gym staff can view own gym history" on "public"."gym_history";

drop policy if exists "Authenticated users can create gyms" on "public"."gyms";

drop policy if exists "Gym staff can update own gym" on "public"."gyms";

drop policy if exists "Gym staff can view own gym" on "public"."gyms";

drop policy if exists "Gym staff can insert activities" on "public"."user_activities";

drop policy if exists "Users and gym staff can view activities" on "public"."user_activities";

drop policy if exists "Gym staff can insert transactions" on "public"."user_gym_transactions";

drop policy if exists "Users and gym staff can view transactions" on "public"."user_gym_transactions";

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "fk_history_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "gym_history_members_churned_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "gym_history_members_gained_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "gym_history_members_retained_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "gym_history_members_total_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" drop constraint "gym_history_revenue_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" drop constraint "gyms_gym_name_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" drop constraint "gyms_stripe_onboarding_status_check";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" drop constraint "fk_activity_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" drop constraint "fk_activity_profile_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" drop constraint "fk_transaction_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" drop constraint "fk_transaction_profile_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

drop function if exists "public"."check_class_plan_ids_gym_match"();

drop function if exists "public"."check_discount_ids_gym_match"();

drop function if exists "public"."check_no_schedule_gaps"();

drop function if exists "public"."enforce_linked_account_hierarchy"();

drop function if exists "public"."gym_has_owner"(p_gym_id uuid);

drop function if exists "public"."is_gym_admin_or_owner"(p_gym_id uuid);

drop function if exists "public"."is_gym_employee"(p_gym_id uuid);

drop view if exists "public"."member_memberships_status";

drop function if exists "public"."prevent_stripe_customer_id_overwrite"();

drop function if exists "public"."prevent_user_id_overwrite"();

drop index if exists "public"."gym_class_exceptions_pkey";

drop index if exists "public"."gym_class_exceptions_schedule_id_original_date_key";

select 1; 
-- drop index if exists "public"."gym_class_schedules_class_id_daterange_excl";

drop index if exists "public"."gym_class_schedules_pkey";

drop index if exists "public"."gym_class_schedules_schedule_id_gym_id_key";

drop index if exists "public"."gym_classes_class_id_gym_id_key";

drop index if exists "public"."gym_classes_log_pkey";

drop index if exists "public"."gym_classes_pkey";

drop index if exists "public"."gym_discounts_pkey";

drop index if exists "public"."gym_employees_employee_id_gym_id_key";

drop index if exists "public"."gym_employees_pkey";

drop index if exists "public"."gym_employees_user_id_gym_id_key";

drop index if exists "public"."gym_rewards_pkey";

drop index if exists "public"."idx_profiles_stripe_customer";

drop index if exists "public"."idx_transactions_stripe_pi";

drop index if exists "public"."idx_webhook_events_gym";

drop index if exists "public"."member_memberships_pkey";

drop index if exists "public"."membership_plans_pkey";

drop index if exists "public"."membership_plans_plan_id_gym_id_key";

drop index if exists "public"."stripe_webhook_events_pkey";

drop index if exists "public"."unique_employee_user_gym";

drop index if exists "public"."unique_user_gym";

drop index if exists "public"."user_gym_profiles_crm_user_id_gym_id_key";

drop index if exists "public"."user_gym_profiles_pkey";

drop index if exists "public"."user_gym_profiles_user_id_gym_id_key";


DROP TABLE IF EXISTS "public"."users_gym_profiles" CASCADE;

create table "public"."users_gym_profiles" (
    "user_id" uuid not null,
    "gym_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "last_class" timestamp with time zone,
    "rank" character varying,
    "account_status" character varying
      );

alter table "public"."users_gym_profiles" enable row level security;

DO $$ BEGIN
  alter table "public"."gyms" drop column "gym_description";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" drop column "stripe_account_id";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" drop column "stripe_onboarding_status";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" add column "owner_id" uuid not null;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" alter column "gym_name" drop not null;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" drop column "crm_user_id";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" add column "user_id" uuid not null;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" drop column "crm_user_id";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" drop column "stripe_invoice_id";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" drop column "stripe_payment_intent_id";
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" add column "user_id" uuid not null;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

drop extension if exists "btree_gist";

DO $$ BEGIN
  CREATE UNIQUE INDEX users_gym_profiles_pkey ON public.users_gym_profiles USING btree (user_id, gym_id);
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."users_gym_profiles" add constraint "users_gym_profiles_pkey" PRIMARY KEY using index "users_gym_profiles_pkey";
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" add constraint "gym_history_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gym_history" validate constraint "gym_history_gym_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" add constraint "gyms_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."gyms" validate constraint "gyms_owner_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" add constraint "user_activities_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" validate constraint "user_activities_gym_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" add constraint "user_activities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" validate constraint "user_activities_user_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" add constraint "user_gym" FOREIGN KEY (user_id, gym_id) REFERENCES public.users_gym_profiles(user_id, gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_activities" validate constraint "user_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" add constraint "user_gym" FOREIGN KEY (user_id, gym_id) REFERENCES public.users_gym_profiles(user_id, gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" validate constraint "user_gym";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_gym_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_user_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."users_gym_profiles" add constraint "users_gym_profiles_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."users_gym_profiles" validate constraint "users_gym_profiles_gym_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."users_gym_profiles" add constraint "users_gym_profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  alter table "public"."users_gym_profiles" validate constraint "users_gym_profiles_user_id_fkey";
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

grant delete on table "public"."users_gym_profiles" to "anon";

grant insert on table "public"."users_gym_profiles" to "anon";

grant references on table "public"."users_gym_profiles" to "anon";

grant select on table "public"."users_gym_profiles" to "anon";

grant trigger on table "public"."users_gym_profiles" to "anon";

grant truncate on table "public"."users_gym_profiles" to "anon";

grant update on table "public"."users_gym_profiles" to "anon";

grant delete on table "public"."users_gym_profiles" to "authenticated";

grant insert on table "public"."users_gym_profiles" to "authenticated";

grant references on table "public"."users_gym_profiles" to "authenticated";

grant select on table "public"."users_gym_profiles" to "authenticated";

grant trigger on table "public"."users_gym_profiles" to "authenticated";

grant truncate on table "public"."users_gym_profiles" to "authenticated";

grant update on table "public"."users_gym_profiles" to "authenticated";

grant delete on table "public"."users_gym_profiles" to "service_role";

grant insert on table "public"."users_gym_profiles" to "service_role";

grant references on table "public"."users_gym_profiles" to "service_role";

grant select on table "public"."users_gym_profiles" to "service_role";

grant trigger on table "public"."users_gym_profiles" to "service_role";

grant truncate on table "public"."users_gym_profiles" to "service_role";

grant update on table "public"."users_gym_profiles" to "service_role";


  drop policy if exists "Gym owners can view own gym history" on "public"."gym_history";
  create policy "Gym owners can view own gym history"
  on "public"."gym_history"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_history.gym_id) AND (gyms.owner_id = auth.uid())))));



  drop policy if exists "Users can update own data" on "public"."gyms";
  create policy "Users can update own data"
  on "public"."gyms"
  as permissive
  for update
  to public
using ((auth.uid() = owner_id))
with check ((auth.uid() = owner_id));



  drop policy if exists "Users can view own data" on "public"."gyms";
  create policy "Users can view own data"
  on "public"."gyms"
  as permissive
  for select
  to public
using ((auth.uid() = owner_id));



  drop policy if exists "Users and gym owners can view activities" on "public"."user_activities";
  create policy "Users and gym owners can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_activities.gym_id) AND (gyms.owner_id = auth.uid()))))));



  drop policy if exists "Users can insert activities for their gyms" on "public"."user_activities";
  create policy "Users can insert activities for their gyms"
  on "public"."user_activities"
  as permissive
  for insert
  to public
with check (((auth.uid() = user_id) AND (EXISTS ( SELECT 1
   FROM public.users_gym_profiles
  WHERE ((users_gym_profiles.user_id = auth.uid()) AND (users_gym_profiles.gym_id = user_activities.gym_id))))));



  drop policy if exists "Users and gym owners can view transactions" on "public"."user_gym_transactions";
  create policy "Users and gym owners can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_transactions.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users and gym owners can update profiles"
  on "public"."users_gym_profiles"
  as permissive
  for update
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = users_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))))
with check (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = users_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users and gym owners can view profiles"
  on "public"."users_gym_profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = users_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))));



