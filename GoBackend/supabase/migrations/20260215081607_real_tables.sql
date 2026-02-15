drop policy "Users can update own data" on "public"."users";

drop policy "Users can view own data" on "public"."users";

revoke delete on table "public"."users" from "anon";

revoke insert on table "public"."users" from "anon";

revoke references on table "public"."users" from "anon";

revoke select on table "public"."users" from "anon";

revoke trigger on table "public"."users" from "anon";

revoke truncate on table "public"."users" from "anon";

revoke update on table "public"."users" from "anon";

revoke delete on table "public"."users" from "authenticated";

revoke insert on table "public"."users" from "authenticated";

revoke references on table "public"."users" from "authenticated";

revoke select on table "public"."users" from "authenticated";

revoke trigger on table "public"."users" from "authenticated";

revoke truncate on table "public"."users" from "authenticated";

revoke update on table "public"."users" from "authenticated";

revoke delete on table "public"."users" from "service_role";

revoke insert on table "public"."users" from "service_role";

revoke references on table "public"."users" from "service_role";

revoke select on table "public"."users" from "service_role";

revoke trigger on table "public"."users" from "service_role";

revoke truncate on table "public"."users" from "service_role";

revoke update on table "public"."users" from "service_role";

alter table "public"."users" drop constraint "users_id_fkey";

drop function if exists "public"."handle_new_user"() cascade;

drop table "public"."users";


  create table "public"."gym_history" (
    "gym_id" uuid not null,
    "date" date not null,
    "members_total" integer not null,
    "members_churned" integer not null,
    "members_gained" integer not null,
    "members_retained" integer not null,
    "revenue" double precision not null
      );


alter table "public"."gym_history" enable row level security;


  create table "public"."gyms" (
    "gym_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_name" character varying,
    "owner_id" uuid not null
      );


alter table "public"."gyms" enable row level security;


  create table "public"."user_activities" (
    "activity_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid not null,
    "gym_id" uuid not null,
    "activity_type" character varying not null,
    "activity_info" jsonb default '{}'::jsonb,
    "time" timestamp with time zone not null default now()
      );


alter table "public"."user_activities" enable row level security;


  create table "public"."user_gym_transactions" (
    "transaction_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid not null,
    "gym_id" uuid not null,
    "item_id" uuid not null,
    "amount_paid" double precision not null,
    "item_type" character varying,
    "time" timestamp with time zone not null default now(),
    "applied_discounts" jsonb,
    "extra_info" jsonb default '{}'::jsonb
      );


alter table "public"."user_gym_transactions" enable row level security;


  create table "public"."user_gym_profiles" (
    "user_id" uuid not null,
    "gym_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "last_class" timestamp with time zone,
    "rank" character varying,
    "account_status" character varying
      );


alter table "public"."user_gym_profiles" enable row level security;

CREATE UNIQUE INDEX gym_history_pkey ON public.gym_history USING btree (gym_id, date);

CREATE UNIQUE INDEX gyms_pkey ON public.gyms USING btree (gym_id);

CREATE UNIQUE INDEX user_activities_pkey ON public.user_activities USING btree (activity_id);

CREATE UNIQUE INDEX user_gym_transactions_pkey ON public.user_gym_transactions USING btree (transaction_id);

CREATE UNIQUE INDEX user_gym_profiles_pkey ON public.user_gym_profiles USING btree (user_id, gym_id);

alter table "public"."gym_history" add constraint "gym_history_pkey" PRIMARY KEY using index "gym_history_pkey";

alter table "public"."gyms" add constraint "gyms_pkey" PRIMARY KEY using index "gyms_pkey";

alter table "public"."user_activities" add constraint "user_activities_pkey" PRIMARY KEY using index "user_activities_pkey";

alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_pkey" PRIMARY KEY using index "user_gym_transactions_pkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_pkey" PRIMARY KEY using index "user_gym_profiles_pkey";

alter table "public"."gym_history" add constraint "gym_history_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_history" validate constraint "gym_history_gym_id_fkey";

alter table "public"."gyms" add constraint "gyms_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) not valid;

alter table "public"."gyms" validate constraint "gyms_owner_id_fkey";

alter table "public"."user_activities" add constraint "user_activities_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_activities" validate constraint "user_activities_gym_id_fkey";

alter table "public"."user_activities" add constraint "user_activities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."user_activities" validate constraint "user_activities_user_id_fkey";

alter table "public"."user_activities" add constraint "user_gym" FOREIGN KEY (user_id, gym_id) REFERENCES public.user_gym_profiles(user_id, gym_id) not valid;

alter table "public"."user_activities" validate constraint "user_gym";

alter table "public"."user_gym_transactions" add constraint "user_gym" FOREIGN KEY (user_id, gym_id) REFERENCES public.user_gym_profiles(user_id, gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "user_gym";

alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_gym_id_fkey";

alter table "public"."user_gym_transactions" add constraint "user_gym_transactions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."user_gym_transactions" validate constraint "user_gym_transactions_user_id_fkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_gym_id_fkey" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_gym_id_fkey";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_user_id_fkey";

grant delete on table "public"."gym_history" to "anon";

grant insert on table "public"."gym_history" to "anon";

grant references on table "public"."gym_history" to "anon";

grant select on table "public"."gym_history" to "anon";

grant trigger on table "public"."gym_history" to "anon";

grant truncate on table "public"."gym_history" to "anon";

grant update on table "public"."gym_history" to "anon";

grant delete on table "public"."gym_history" to "authenticated";

grant insert on table "public"."gym_history" to "authenticated";

grant references on table "public"."gym_history" to "authenticated";

grant select on table "public"."gym_history" to "authenticated";

grant trigger on table "public"."gym_history" to "authenticated";

grant truncate on table "public"."gym_history" to "authenticated";

grant update on table "public"."gym_history" to "authenticated";

grant delete on table "public"."gym_history" to "service_role";

grant insert on table "public"."gym_history" to "service_role";

grant references on table "public"."gym_history" to "service_role";

grant select on table "public"."gym_history" to "service_role";

grant trigger on table "public"."gym_history" to "service_role";

grant truncate on table "public"."gym_history" to "service_role";

grant update on table "public"."gym_history" to "service_role";

grant delete on table "public"."gyms" to "anon";

grant insert on table "public"."gyms" to "anon";

grant references on table "public"."gyms" to "anon";

grant select on table "public"."gyms" to "anon";

grant trigger on table "public"."gyms" to "anon";

grant truncate on table "public"."gyms" to "anon";

grant update on table "public"."gyms" to "anon";

grant delete on table "public"."gyms" to "authenticated";

grant insert on table "public"."gyms" to "authenticated";

grant references on table "public"."gyms" to "authenticated";

grant select on table "public"."gyms" to "authenticated";

grant trigger on table "public"."gyms" to "authenticated";

grant truncate on table "public"."gyms" to "authenticated";

grant update on table "public"."gyms" to "authenticated";

grant delete on table "public"."gyms" to "service_role";

grant insert on table "public"."gyms" to "service_role";

grant references on table "public"."gyms" to "service_role";

grant select on table "public"."gyms" to "service_role";

grant trigger on table "public"."gyms" to "service_role";

grant truncate on table "public"."gyms" to "service_role";

grant update on table "public"."gyms" to "service_role";

grant delete on table "public"."user_activities" to "anon";

grant insert on table "public"."user_activities" to "anon";

grant references on table "public"."user_activities" to "anon";

grant select on table "public"."user_activities" to "anon";

grant trigger on table "public"."user_activities" to "anon";

grant truncate on table "public"."user_activities" to "anon";

grant update on table "public"."user_activities" to "anon";

grant delete on table "public"."user_activities" to "authenticated";

grant insert on table "public"."user_activities" to "authenticated";

grant references on table "public"."user_activities" to "authenticated";

grant select on table "public"."user_activities" to "authenticated";

grant trigger on table "public"."user_activities" to "authenticated";

grant truncate on table "public"."user_activities" to "authenticated";

grant update on table "public"."user_activities" to "authenticated";

grant delete on table "public"."user_activities" to "service_role";

grant insert on table "public"."user_activities" to "service_role";

grant references on table "public"."user_activities" to "service_role";

grant select on table "public"."user_activities" to "service_role";

grant trigger on table "public"."user_activities" to "service_role";

grant truncate on table "public"."user_activities" to "service_role";

grant update on table "public"."user_activities" to "service_role";

grant delete on table "public"."user_gym_transactions" to "anon";

grant insert on table "public"."user_gym_transactions" to "anon";

grant references on table "public"."user_gym_transactions" to "anon";

grant select on table "public"."user_gym_transactions" to "anon";

grant trigger on table "public"."user_gym_transactions" to "anon";

grant truncate on table "public"."user_gym_transactions" to "anon";

grant update on table "public"."user_gym_transactions" to "anon";

grant delete on table "public"."user_gym_transactions" to "authenticated";

grant insert on table "public"."user_gym_transactions" to "authenticated";

grant references on table "public"."user_gym_transactions" to "authenticated";

grant select on table "public"."user_gym_transactions" to "authenticated";

grant trigger on table "public"."user_gym_transactions" to "authenticated";

grant truncate on table "public"."user_gym_transactions" to "authenticated";

grant update on table "public"."user_gym_transactions" to "authenticated";

grant delete on table "public"."user_gym_transactions" to "service_role";

grant insert on table "public"."user_gym_transactions" to "service_role";

grant references on table "public"."user_gym_transactions" to "service_role";

grant select on table "public"."user_gym_transactions" to "service_role";

grant trigger on table "public"."user_gym_transactions" to "service_role";

grant truncate on table "public"."user_gym_transactions" to "service_role";

grant update on table "public"."user_gym_transactions" to "service_role";

grant delete on table "public"."user_gym_profiles" to "anon";

grant insert on table "public"."user_gym_profiles" to "anon";

grant references on table "public"."user_gym_profiles" to "anon";

grant select on table "public"."user_gym_profiles" to "anon";

grant trigger on table "public"."user_gym_profiles" to "anon";

grant truncate on table "public"."user_gym_profiles" to "anon";

grant update on table "public"."user_gym_profiles" to "anon";

grant delete on table "public"."user_gym_profiles" to "authenticated";

grant insert on table "public"."user_gym_profiles" to "authenticated";

grant references on table "public"."user_gym_profiles" to "authenticated";

grant select on table "public"."user_gym_profiles" to "authenticated";

grant trigger on table "public"."user_gym_profiles" to "authenticated";

grant truncate on table "public"."user_gym_profiles" to "authenticated";

grant update on table "public"."user_gym_profiles" to "authenticated";

grant delete on table "public"."user_gym_profiles" to "service_role";

grant insert on table "public"."user_gym_profiles" to "service_role";

grant references on table "public"."user_gym_profiles" to "service_role";

grant select on table "public"."user_gym_profiles" to "service_role";

grant trigger on table "public"."user_gym_profiles" to "service_role";

grant truncate on table "public"."user_gym_profiles" to "service_role";

grant update on table "public"."user_gym_profiles" to "service_role";


  create policy "Gym owners can view own gym history"
  on "public"."gym_history"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = gym_history.gym_id) AND (gyms.owner_id = auth.uid())))));



  create policy "Users can update own data"
  on "public"."gyms"
  as permissive
  for update
  to public
using ((auth.uid() = owner_id))
with check ((auth.uid() = owner_id));



  create policy "Users can view own data"
  on "public"."gyms"
  as permissive
  for select
  to public
using ((auth.uid() = owner_id));



  create policy "Users and gym owners can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_activities.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users can insert activities for their gyms"
  on "public"."user_activities"
  as permissive
  for insert
  to public
with check (((auth.uid() = user_id) AND (EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.user_id = auth.uid()) AND (user_gym_profiles.gym_id = user_activities.gym_id))))));



  create policy "Users and gym owners can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_transactions.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users and gym owners can update profiles"
  on "public"."user_gym_profiles"
  as permissive
  for update
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))))
with check (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))));



  create policy "Users and gym owners can view profiles"
  on "public"."user_gym_profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gyms
  WHERE ((gyms.gym_id = user_gym_profiles.gym_id) AND (gyms.owner_id = auth.uid()))))));


drop trigger if exists "on_auth_user_created" on "auth"."users";
