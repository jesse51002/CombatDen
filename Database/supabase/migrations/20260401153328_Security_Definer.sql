drop policy "Gym staff can insert discounts" on "public"."gym_discounts";

drop policy "Gym staff can update discounts" on "public"."gym_discounts";

drop policy "Gym staff can view discounts" on "public"."gym_discounts";

drop policy "Employees can view gym staff" on "public"."gym_employees";

drop policy "Owners and admins can insert employees" on "public"."gym_employees";

drop policy "Owners and admins can update employees" on "public"."gym_employees";

drop policy "Gym staff can view own gym history" on "public"."gym_history";

drop policy "Gym staff can insert rewards" on "public"."gym_rewards";

drop policy "Gym staff can update rewards" on "public"."gym_rewards";

drop policy "Gym staff can view rewards" on "public"."gym_rewards";

drop policy "Gym staff can update own gym" on "public"."gyms";

drop policy "Gym staff can view own gym" on "public"."gyms";

drop policy "Gym staff can insert memberships" on "public"."member_memberships";

drop policy "Gym staff can update memberships" on "public"."member_memberships";

drop policy "Gym staff can view memberships" on "public"."member_memberships";

drop policy "Gym staff can insert plans" on "public"."membership_plans";

drop policy "Gym staff can update plans" on "public"."membership_plans";

drop policy "Gym staff can view plans" on "public"."membership_plans";

drop policy "Gym staff can insert activities" on "public"."user_activities";

drop policy "Users and gym staff can view activities" on "public"."user_activities";

drop policy "Gym staff can insert profiles" on "public"."user_gym_profiles";

drop policy "Users and gym staff can update profiles" on "public"."user_gym_profiles";

drop policy "Users and gym staff can view profiles" on "public"."user_gym_profiles";

drop policy "Gym staff can insert transactions" on "public"."user_gym_transactions";

drop policy "Users and gym staff can view transactions" on "public"."user_gym_transactions";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.gym_has_owner(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.employee_type = 'owner'
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_gym_admin_or_owner(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
        AND gym_employees.employee_type IN ('owner', 'admin')
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_gym_employee(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
    );
$function$
;


  create policy "Gym staff can insert discounts"
  on "public"."gym_discounts"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update discounts"
  on "public"."gym_discounts"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view discounts"
  on "public"."gym_discounts"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Employees can view gym staff"
  on "public"."gym_employees"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Owners and admins can insert employees"
  on "public"."gym_employees"
  as permissive
  for insert
  to authenticated
with check ((public.is_gym_admin_or_owner(gym_id) OR (((employee_type)::text = 'owner'::text) AND (user_id = auth.uid()) AND (NOT public.gym_has_owner(gym_id)))));



  create policy "Owners and admins can update employees"
  on "public"."gym_employees"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view own gym history"
  on "public"."gym_history"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert rewards"
  on "public"."gym_rewards"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update rewards"
  on "public"."gym_rewards"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update own gym"
  on "public"."gyms"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view own gym"
  on "public"."gyms"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert memberships"
  on "public"."member_memberships"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update memberships"
  on "public"."member_memberships"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view memberships"
  on "public"."member_memberships"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert plans"
  on "public"."membership_plans"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update plans"
  on "public"."membership_plans"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view plans"
  on "public"."membership_plans"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert activities"
  on "public"."user_activities"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view activities"
  on "public"."user_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_activities.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can insert profiles"
  on "public"."user_gym_profiles"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can update profiles"
  on "public"."user_gym_profiles"
  as permissive
  for update
  to public
using (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)))
with check (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view profiles"
  on "public"."user_gym_profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can insert transactions"
  on "public"."user_gym_transactions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view transactions"
  on "public"."user_gym_transactions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



