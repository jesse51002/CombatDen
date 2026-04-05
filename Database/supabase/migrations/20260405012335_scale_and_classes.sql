create extension if not exists "btree_gist" with schema "public";

drop policy "Gym staff can update memberships" on "public"."member_memberships";

revoke update on table "public"."member_memberships" from "authenticated";

alter table "public"."gym_discounts" drop constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

drop view if exists "public"."member_memberships_status";


  create table "public"."gym_class_exceptions" (
    "exception_id" uuid not null default extensions.uuid_generate_v4(),
    "schedule_id" uuid not null,
    "gym_id" uuid not null,
    "original_date" date not null,
    "is_cancelled" boolean,
    "new_class_time" time without time zone,
    "new_duration_minutes" integer,
    "new_max_capacity" integer,
    "new_instructor_id" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_class_exceptions" enable row level security;


  create table "public"."gym_class_schedules" (
    "schedule_id" uuid not null default extensions.uuid_generate_v4(),
    "class_id" uuid not null,
    "gym_id" uuid not null,
    "class_time" time without time zone not null,
    "duration_minutes" integer not null,
    "recurring_unit" character varying not null,
    "recurring_interval" integer not null default 1,
    "sun" boolean not null default false,
    "mon" boolean not null default false,
    "tue" boolean not null default false,
    "wed" boolean not null default false,
    "thu" boolean not null default false,
    "fri" boolean not null default false,
    "sat" boolean not null default false,
    "sun_instructor_id" uuid,
    "mon_instructor_id" uuid,
    "tue_instructor_id" uuid,
    "wed_instructor_id" uuid,
    "thu_instructor_id" uuid,
    "fri_instructor_id" uuid,
    "sat_instructor_id" uuid,
    "is_cancelled" boolean not null default false,
    "start_date" date not null,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_class_schedules" enable row level security;


  create table "public"."gym_classes" (
    "class_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "class_name" character varying not null,
    "class_description" character varying,
    "allowed_plan_ids" jsonb,
    "max_capacity" integer,
    "is_active" boolean not null default true,
    "is_deleted" boolean not null default false,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_classes" enable row level security;


  create table "public"."gym_classes_log" (
    "log_id" uuid not null default extensions.uuid_generate_v4(),
    "crm_user_id" uuid not null,
    "gym_id" uuid not null,
    "class_id" uuid not null,
    "plan_id" uuid not null,
    "instructor_id" uuid,
    "time" timestamp with time zone not null default now()
      );


alter table "public"."gym_classes_log" enable row level security;

alter table "public"."gym_employees" add column "employee_pic_url" character varying;

alter table "public"."gym_employees" add column "employee_public_description" character varying;

alter table "public"."gyms" add column "gym_description" character varying;

alter table "public"."member_memberships" add column "price_formula" character varying;

alter table "public"."user_gym_profiles" add column "streak" integer not null default 0;

CREATE UNIQUE INDEX gym_class_exceptions_pkey ON public.gym_class_exceptions USING btree (exception_id);

CREATE UNIQUE INDEX gym_class_exceptions_schedule_id_original_date_key ON public.gym_class_exceptions USING btree (schedule_id, original_date);

select 1; 
-- CREATE INDEX gym_class_schedules_class_id_daterange_excl ON public.gym_class_schedules USING gist (class_id, daterange(start_date, end_date, '[]'::text));

CREATE UNIQUE INDEX gym_class_schedules_pkey ON public.gym_class_schedules USING btree (schedule_id);

CREATE UNIQUE INDEX gym_class_schedules_schedule_id_gym_id_key ON public.gym_class_schedules USING btree (schedule_id, gym_id);

CREATE UNIQUE INDEX gym_classes_class_id_gym_id_key ON public.gym_classes USING btree (class_id, gym_id);

CREATE UNIQUE INDEX gym_classes_log_pkey ON public.gym_classes_log USING btree (log_id);

CREATE UNIQUE INDEX gym_classes_pkey ON public.gym_classes USING btree (class_id);

CREATE UNIQUE INDEX gym_employees_employee_id_gym_id_key ON public.gym_employees USING btree (employee_id, gym_id);

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_pkey" PRIMARY KEY using index "gym_class_exceptions_pkey";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_pkey" PRIMARY KEY using index "gym_class_schedules_pkey";

alter table "public"."gym_classes" add constraint "gym_classes_pkey" PRIMARY KEY using index "gym_classes_pkey";

alter table "public"."gym_classes_log" add constraint "gym_classes_log_pkey" PRIMARY KEY using index "gym_classes_log_pkey";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_gym";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_instructor" FOREIGN KEY (new_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_instructor";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_schedule" FOREIGN KEY (schedule_id, gym_id) REFERENCES public.gym_class_schedules(schedule_id, gym_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_schedule";

alter table "public"."gym_class_exceptions" add constraint "fk_exception_schedule_id" FOREIGN KEY (schedule_id) REFERENCES public.gym_class_schedules(schedule_id) not valid;

alter table "public"."gym_class_exceptions" validate constraint "fk_exception_schedule_id";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_new_duration_minutes_check" CHECK ((new_duration_minutes > 0)) not valid;

alter table "public"."gym_class_exceptions" validate constraint "gym_class_exceptions_new_duration_minutes_check";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_new_max_capacity_check" CHECK ((new_max_capacity > 0)) not valid;

alter table "public"."gym_class_exceptions" validate constraint "gym_class_exceptions_new_max_capacity_check";

alter table "public"."gym_class_exceptions" add constraint "gym_class_exceptions_schedule_id_original_date_key" UNIQUE using index "gym_class_exceptions_schedule_id_original_date_key";

alter table "public"."gym_class_schedules" add constraint "fk_sched_fri_instructor" FOREIGN KEY (fri_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_fri_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_mon_instructor" FOREIGN KEY (mon_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_mon_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_sat_instructor" FOREIGN KEY (sat_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_sat_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_sun_instructor" FOREIGN KEY (sun_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_sun_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_thu_instructor" FOREIGN KEY (thu_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_thu_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_tue_instructor" FOREIGN KEY (tue_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_tue_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_sched_wed_instructor" FOREIGN KEY (wed_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_sched_wed_instructor";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_class";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_class_id";

alter table "public"."gym_class_schedules" add constraint "fk_schedule_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_class_schedules" validate constraint "fk_schedule_gym";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_check" CHECK (((end_date IS NULL) OR (end_date >= start_date))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_check1" CHECK ((((recurring_unit)::text <> 'weekly'::text) OR sun OR mon OR tue OR wed OR thu OR fri OR sat)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_check1";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_class_id_daterange_excl" EXCLUDE USING gist (class_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_duration_minutes_check" CHECK ((duration_minutes > 0)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_duration_minutes_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_interval_check" CHECK ((recurring_interval > 0)) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_interval_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_schedule_id_gym_id_key" UNIQUE using index "gym_class_schedules_schedule_id_gym_id_key";

alter table "public"."gym_classes" add constraint "fk_class_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_gym";

alter table "public"."gym_classes" add constraint "gym_classes_class_id_gym_id_key" UNIQUE using index "gym_classes_class_id_gym_id_key";

alter table "public"."gym_classes" add constraint "gym_classes_class_name_check" CHECK (((class_name)::text <> ''::text)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_class_name_check";

alter table "public"."gym_classes" add constraint "gym_classes_max_capacity_check" CHECK ((max_capacity > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_max_capacity_check";

alter table "public"."gym_classes_log" add constraint "fk_class_log_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_class";

alter table "public"."gym_classes_log" add constraint "fk_class_log_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_class_id";

alter table "public"."gym_classes_log" add constraint "fk_class_log_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_gym";

alter table "public"."gym_classes_log" add constraint "fk_class_log_instructor" FOREIGN KEY (instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_instructor";

alter table "public"."gym_classes_log" add constraint "fk_class_log_membership" FOREIGN KEY (crm_user_id, gym_id, plan_id) REFERENCES public.member_memberships(crm_user_id, gym_id, plan_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_membership";

alter table "public"."gym_classes_log" add constraint "fk_class_log_plan_id" FOREIGN KEY (plan_id) REFERENCES public.membership_plans(plan_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_plan_id";

alter table "public"."gym_classes_log" add constraint "fk_class_log_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_profile_gym";

alter table "public"."gym_employees" add constraint "gym_employees_employee_id_gym_id_key" UNIQUE using index "gym_employees_employee_id_gym_id_key";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_streak_check" CHECK ((streak >= 0)) not valid;

alter table "public"."user_gym_profiles" validate constraint "user_gym_profiles_streak_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['membership'::character varying, 'custom'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_class_plan_ids_gym_match()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    plan_id_text TEXT;
    plan_uuid UUID;
BEGIN
    IF NEW.allowed_plan_ids IS NOT NULL AND jsonb_array_length(NEW.allowed_plan_ids) > 0 THEN
        FOR plan_id_text IN SELECT jsonb_array_elements_text(NEW.allowed_plan_ids)
        LOOP
            plan_uuid := plan_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM membership_plans
                WHERE plan_id = plan_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'plan_id % does not belong to gym_id %', plan_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_no_schedule_gaps()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    target_class_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_class_id := OLD.class_id;
    ELSE
        target_class_id := NEW.class_id;
    END IF;

    -- Skip check if no segments remain for this class
    IF NOT EXISTS (
        SELECT 1 FROM gym_class_schedules WHERE class_id = target_class_id
    ) THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Check for gaps: any segment that ends without another starting the next day
    IF EXISTS (
        SELECT 1
        FROM gym_class_schedules a
        LEFT JOIN gym_class_schedules b
            ON b.class_id = a.class_id
            AND b.start_date = a.end_date + 1
        WHERE a.class_id = target_class_id
            AND a.end_date IS NOT NULL
            AND b.schedule_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Gap detected in schedule for class %', target_class_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$
;

create or replace view "public"."member_memberships_status" as  SELECT crm_user_id,
    gym_id,
    plan_id,
    start_date,
    end_date,
    cancel_date,
    freeze_start_date,
    freeze_end_date,
    last_paid_date,
    next_due_date,
    discount_ids,
    total_price,
    price_formula,
    created_at,
        CASE
            WHEN ((cancel_date IS NOT NULL) AND (cancel_date <= CURRENT_DATE)) THEN 'cancelled'::text
            WHEN ((end_date IS NOT NULL) AND (end_date <= CURRENT_DATE)) THEN 'ended'::text
            WHEN ((freeze_start_date IS NOT NULL) AND (freeze_end_date IS NOT NULL) AND (freeze_start_date <= CURRENT_DATE) AND (CURRENT_DATE <= freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM public.member_memberships;


grant delete on table "public"."gym_class_exceptions" to "anon";

grant insert on table "public"."gym_class_exceptions" to "anon";

grant references on table "public"."gym_class_exceptions" to "anon";

grant select on table "public"."gym_class_exceptions" to "anon";

grant trigger on table "public"."gym_class_exceptions" to "anon";

grant truncate on table "public"."gym_class_exceptions" to "anon";

grant update on table "public"."gym_class_exceptions" to "anon";

grant delete on table "public"."gym_class_exceptions" to "authenticated";

grant insert on table "public"."gym_class_exceptions" to "authenticated";

grant references on table "public"."gym_class_exceptions" to "authenticated";

grant select on table "public"."gym_class_exceptions" to "authenticated";

grant trigger on table "public"."gym_class_exceptions" to "authenticated";

grant truncate on table "public"."gym_class_exceptions" to "authenticated";

grant update on table "public"."gym_class_exceptions" to "authenticated";

grant delete on table "public"."gym_class_exceptions" to "service_role";

grant insert on table "public"."gym_class_exceptions" to "service_role";

grant references on table "public"."gym_class_exceptions" to "service_role";

grant select on table "public"."gym_class_exceptions" to "service_role";

grant trigger on table "public"."gym_class_exceptions" to "service_role";

grant truncate on table "public"."gym_class_exceptions" to "service_role";

grant update on table "public"."gym_class_exceptions" to "service_role";

grant delete on table "public"."gym_class_schedules" to "anon";

grant insert on table "public"."gym_class_schedules" to "anon";

grant references on table "public"."gym_class_schedules" to "anon";

grant select on table "public"."gym_class_schedules" to "anon";

grant trigger on table "public"."gym_class_schedules" to "anon";

grant truncate on table "public"."gym_class_schedules" to "anon";

grant update on table "public"."gym_class_schedules" to "anon";

grant delete on table "public"."gym_class_schedules" to "authenticated";

grant insert on table "public"."gym_class_schedules" to "authenticated";

grant references on table "public"."gym_class_schedules" to "authenticated";

grant select on table "public"."gym_class_schedules" to "authenticated";

grant trigger on table "public"."gym_class_schedules" to "authenticated";

grant truncate on table "public"."gym_class_schedules" to "authenticated";

grant update on table "public"."gym_class_schedules" to "authenticated";

grant delete on table "public"."gym_class_schedules" to "service_role";

grant insert on table "public"."gym_class_schedules" to "service_role";

grant references on table "public"."gym_class_schedules" to "service_role";

grant select on table "public"."gym_class_schedules" to "service_role";

grant trigger on table "public"."gym_class_schedules" to "service_role";

grant truncate on table "public"."gym_class_schedules" to "service_role";

grant update on table "public"."gym_class_schedules" to "service_role";

grant delete on table "public"."gym_classes" to "anon";

grant insert on table "public"."gym_classes" to "anon";

grant references on table "public"."gym_classes" to "anon";

grant select on table "public"."gym_classes" to "anon";

grant trigger on table "public"."gym_classes" to "anon";

grant truncate on table "public"."gym_classes" to "anon";

grant update on table "public"."gym_classes" to "anon";

grant delete on table "public"."gym_classes" to "authenticated";

grant insert on table "public"."gym_classes" to "authenticated";

grant references on table "public"."gym_classes" to "authenticated";

grant select on table "public"."gym_classes" to "authenticated";

grant trigger on table "public"."gym_classes" to "authenticated";

grant truncate on table "public"."gym_classes" to "authenticated";

grant update on table "public"."gym_classes" to "authenticated";

grant delete on table "public"."gym_classes" to "service_role";

grant insert on table "public"."gym_classes" to "service_role";

grant references on table "public"."gym_classes" to "service_role";

grant select on table "public"."gym_classes" to "service_role";

grant trigger on table "public"."gym_classes" to "service_role";

grant truncate on table "public"."gym_classes" to "service_role";

grant update on table "public"."gym_classes" to "service_role";

grant delete on table "public"."gym_classes_log" to "anon";

grant insert on table "public"."gym_classes_log" to "anon";

grant references on table "public"."gym_classes_log" to "anon";

grant select on table "public"."gym_classes_log" to "anon";

grant trigger on table "public"."gym_classes_log" to "anon";

grant truncate on table "public"."gym_classes_log" to "anon";

grant update on table "public"."gym_classes_log" to "anon";

grant delete on table "public"."gym_classes_log" to "authenticated";

grant insert on table "public"."gym_classes_log" to "authenticated";

grant references on table "public"."gym_classes_log" to "authenticated";

grant select on table "public"."gym_classes_log" to "authenticated";

grant trigger on table "public"."gym_classes_log" to "authenticated";

grant truncate on table "public"."gym_classes_log" to "authenticated";

grant delete on table "public"."gym_classes_log" to "service_role";

grant insert on table "public"."gym_classes_log" to "service_role";

grant references on table "public"."gym_classes_log" to "service_role";

grant select on table "public"."gym_classes_log" to "service_role";

grant trigger on table "public"."gym_classes_log" to "service_role";

grant truncate on table "public"."gym_classes_log" to "service_role";

grant update on table "public"."gym_classes_log" to "service_role";


  create policy "Gym employees can view exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view exceptions"
  on "public"."gym_class_exceptions"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_class_exceptions.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym employees can view schedules"
  on "public"."gym_class_schedules"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert schedules"
  on "public"."gym_class_schedules"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update schedules"
  on "public"."gym_class_schedules"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



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



  create policy "Gym employees can view classes"
  on "public"."gym_classes"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert classes"
  on "public"."gym_classes"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update classes"
  on "public"."gym_classes"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view classes"
  on "public"."gym_classes"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.gym_id = gym_classes.gym_id) AND (user_gym_profiles.user_id = auth.uid())))));



  create policy "Gym staff can insert class logs"
  on "public"."gym_classes_log"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view class logs"
  on "public"."gym_classes_log"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.user_gym_profiles
  WHERE ((user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id) AND (user_gym_profiles.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));


CREATE TRIGGER trg_enforce_no_schedule_gaps AFTER INSERT OR DELETE OR UPDATE ON public.gym_class_schedules FOR EACH ROW EXECUTE FUNCTION public.check_no_schedule_gaps();

CREATE TRIGGER trg_check_class_plan_ids_gym_match BEFORE INSERT OR UPDATE OF allowed_plan_ids ON public.gym_classes FOR EACH ROW EXECUTE FUNCTION public.check_class_plan_ids_gym_match();


