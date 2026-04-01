drop policy "Gym owners can insert discounts" on "public"."gym_discounts";

drop policy "Gym owners can update discounts" on "public"."gym_discounts";

drop policy "Gym owners can view discounts" on "public"."gym_discounts";

drop policy "Gym owners can view own gym history" on "public"."gym_history";

drop policy "Gym owners can insert rewards" on "public"."gym_rewards";

drop policy "Gym owners can update rewards" on "public"."gym_rewards";

drop policy "Gym owners can view rewards" on "public"."gym_rewards";

drop policy "Owners can insert their own gyms" on "public"."gyms";

drop policy "Users can update own data" on "public"."gyms";

drop policy "Users can view own data" on "public"."gyms";

drop policy "Gym owners can insert memberships" on "public"."member_memberships";

drop policy "Gym owners can update memberships" on "public"."member_memberships";

drop policy "Gym owners can view memberships" on "public"."member_memberships";

drop policy "Gym owners can insert plans" on "public"."membership_plans";

drop policy "Gym owners can update plans" on "public"."membership_plans";

drop policy "Gym owners can view plans" on "public"."membership_plans";

drop policy "Gym owners can insert activities" on "public"."user_activities";

drop policy "Users and gym owners can view activities" on "public"."user_activities";

drop policy "Gym owners can insert profiles" on "public"."user_gym_profiles";

drop policy "Users and gym owners can update profiles" on "public"."user_gym_profiles";

drop policy "Users and gym owners can view profiles" on "public"."user_gym_profiles";

drop policy "Gym owners can insert transactions" on "public"."user_gym_transactions";

drop policy "Users and gym owners can view transactions" on "public"."user_gym_transactions";

alter table "public"."gyms" drop constraint "fk_gyms_owner";

alter table "public"."gyms" drop constraint "gyms_owner_id_key";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

drop index if exists "public"."gyms_owner_id_key";


  create table "public"."gym_employees" (
    "employee_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid,
    "gym_id" uuid not null,
    "employee_type" character varying not null,
    "first_name" character varying not null,
    "last_name" character varying not null,
    "phone" character varying,
    "email" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_employees" enable row level security;

alter table "public"."gyms" drop column "owner_id";

CREATE UNIQUE INDEX gym_employees_pkey ON public.gym_employees USING btree (employee_id);

CREATE UNIQUE INDEX gym_employees_user_id_gym_id_key ON public.gym_employees USING btree (user_id, gym_id);

CREATE UNIQUE INDEX unique_employee_user_gym ON public.gym_employees USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

alter table "public"."gym_employees" add constraint "gym_employees_pkey" PRIMARY KEY using index "gym_employees_pkey";

alter table "public"."gym_employees" add constraint "fk_employee_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_gym";

alter table "public"."gym_employees" add constraint "fk_employee_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_user";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_first_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_last_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_user_id_gym_id_key" UNIQUE using index "gym_employees_user_id_gym_id_key";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";

grant delete on table "public"."gym_employees" to "anon";

grant insert on table "public"."gym_employees" to "anon";

grant references on table "public"."gym_employees" to "anon";

grant select on table "public"."gym_employees" to "anon";

grant trigger on table "public"."gym_employees" to "anon";

grant truncate on table "public"."gym_employees" to "anon";

grant update on table "public"."gym_employees" to "anon";

grant delete on table "public"."gym_employees" to "authenticated";

grant insert on table "public"."gym_employees" to "authenticated";

grant references on table "public"."gym_employees" to "authenticated";

grant select on table "public"."gym_employees" to "authenticated";

grant trigger on table "public"."gym_employees" to "authenticated";

grant truncate on table "public"."gym_employees" to "authenticated";

grant update on table "public"."gym_employees" to "authenticated";

grant delete on table "public"."gym_employees" to "service_role";

grant insert on table "public"."gym_employees" to "service_role";

grant references on table "public"."gym_employees" to "service_role";

grant select on table "public"."gym_employees" to "service_role";

grant trigger on table "public"."gym_employees" to "service_role";

grant truncate on table "public"."gym_employees" to "service_role";

grant update on table "public"."gym_employees" to "service_role";


  create policy "Gym staff can insert discounts"
  on "public"."gym_discounts"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_discounts.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can update discounts"
  on "public"."gym_discounts"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_discounts.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_discounts.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view discounts"
  on "public"."gym_discounts"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_discounts.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Employees can view gym staff"
  on "public"."gym_employees"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees self
  WHERE ((self.gym_id = gym_employees.gym_id) AND (self.user_id = auth.uid())))));



  create policy "Owners and admins can insert employees"
  on "public"."gym_employees"
  as permissive
  for insert
  to authenticated
with check (((EXISTS ( SELECT 1
   FROM public.gym_employees self
  WHERE ((self.gym_id = gym_employees.gym_id) AND (self.user_id = auth.uid()) AND ((self.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))) OR (((employee_type)::text = 'owner'::text) AND (user_id = auth.uid()) AND (NOT (EXISTS ( SELECT 1
   FROM public.gym_employees existing
  WHERE ((existing.gym_id = gym_employees.gym_id) AND ((existing.employee_type)::text = 'owner'::text))))))));



  create policy "Owners and admins can update employees"
  on "public"."gym_employees"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees self
  WHERE ((self.gym_id = gym_employees.gym_id) AND (self.user_id = auth.uid()) AND ((self.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees self
  WHERE ((self.gym_id = gym_employees.gym_id) AND (self.user_id = auth.uid()) AND ((self.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view own gym history"
  on "public"."gym_history"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_history.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can insert rewards"
  on "public"."gym_rewards"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_rewards.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can update rewards"
  on "public"."gym_rewards"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_rewards.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_rewards.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gym_rewards.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Authenticated users can create gyms"
  on "public"."gyms"
  as permissive
  for insert
  to authenticated
with check (true);



  create policy "Gym staff can update own gym"
  on "public"."gyms"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gyms.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gyms.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view own gym"
  on "public"."gyms"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = gyms.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can insert memberships"
  on "public"."member_memberships"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = member_memberships.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can update memberships"
  on "public"."member_memberships"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = member_memberships.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = member_memberships.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = member_memberships.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can insert plans"
  on "public"."membership_plans"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = membership_plans.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can update plans"
  on "public"."membership_plans"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = membership_plans.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))))
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = membership_plans.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can view plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = membership_plans.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Gym staff can insert activities"
  on "public"."user_activities"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_activities.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Users and gym staff can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_activities.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[])))))));



  create policy "Gym staff can insert profiles"
  on "public"."user_gym_profiles"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_profiles.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Users and gym staff can update profiles"
  on "public"."user_gym_profiles"
  as permissive
  for update
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_profiles.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[])))))))
with check (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_profiles.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[])))))));



  create policy "Users and gym staff can view profiles"
  on "public"."user_gym_profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_profiles.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[])))))));



  create policy "Gym staff can insert transactions"
  on "public"."user_gym_transactions"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_transactions.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[]))))));



  create policy "Users and gym staff can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.gym_employees
  WHERE ((gym_employees.gym_id = user_gym_transactions.gym_id) AND (gym_employees.user_id = auth.uid()) AND ((gym_employees.employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::text[])))))));



