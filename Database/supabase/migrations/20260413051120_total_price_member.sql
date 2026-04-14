


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."charge_kind" AS ENUM (
    'payment',
    'refund'
);


ALTER TYPE "public"."charge_kind" OWNER TO "postgres";


CREATE TYPE "public"."charge_status" AS ENUM (
    'pending',
    'succeeded',
    'failed'
);


ALTER TYPE "public"."charge_status" OWNER TO "postgres";


CREATE TYPE "public"."invoice_status" AS ENUM (
    'open',
    'paid'
);


ALTER TYPE "public"."invoice_status" OWNER TO "postgres";


CREATE TYPE "public"."line_item_type" AS ENUM (
    'membership',
    'custom'
);


ALTER TYPE "public"."line_item_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_class_plan_ids_gym_match"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    plan_id_text TEXT;
    plan_uuid UUID;
BEGIN
    IF NEW.allowed_plan_ids IS NOT NULL AND jsonb_array_length(NEW.allowed_plan_ids) > 0 THEN
        FOR plan_id_text IN SELECT jsonb_array_elements_text(NEW.allowed_plan_ids)
        LOOP
            plan_uuid := plan_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM membership_plans_unfiltered
                WHERE plan_id = plan_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'plan_id % does not belong to gym_id %', plan_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_class_plan_ids_gym_match"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_discount_ids_gym_match"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    discount_id_text TEXT;
    discount_uuid UUID;
BEGIN
    IF NEW.discount_ids IS NOT NULL AND jsonb_array_length(NEW.discount_ids) > 0 THEN
        FOR discount_id_text IN SELECT jsonb_array_elements_text(NEW.discount_ids)
        LOOP
            discount_uuid := discount_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM gym_discounts_unfiltered
                WHERE discount_id = discount_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'discount_id % does not belong to gym_id %', discount_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_discount_ids_gym_match"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_linked_discount_type"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.linked_discount_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM gym_discounts_unfiltered
            WHERE discount_id = NEW.linked_discount_id
              AND discount_type = 'linked'
        ) THEN
            RAISE EXCEPTION 'linked_discount_id % must reference a discount with type linked', NEW.linked_discount_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_linked_discount_type"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_no_schedule_gaps"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."check_no_schedule_gaps"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_recurring_chronological_start_date"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_plan_type VARCHAR;
    v_max_start_date DATE;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships_unfiltered mm
        WHERE mm.crm_user_id = NEW.crm_user_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id;

        IF v_max_start_date IS NOT NULL AND NEW.start_date <= v_max_start_date THEN
            RAISE EXCEPTION 'start_date must be after % (latest existing start_date for this plan)', v_max_start_date
                USING CONSTRAINT = 'recurring_chronological_start_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_recurring_chronological_start_date"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_recurring_no_active_memberships"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_plan_type VARCHAR;
    v_active_count INTEGER;
    v_today DATE;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT (now() AT TIME ZONE g.timezone)::date INTO v_today
        FROM gyms g WHERE g.gym_id = NEW.gym_id;

        SELECT COUNT(*) INTO v_active_count
        FROM member_memberships_unfiltered mm
        WHERE mm.crm_user_id = NEW.crm_user_id
          AND mm.gym_id = NEW.gym_id
          AND mm.item_id <> NEW.item_id
          AND (mm.cancel_date IS NULL OR mm.cancel_date > v_today)
          AND (mm.end_date IS NULL OR mm.end_date > v_today);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while active memberships exist'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_recurring_no_active_memberships"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_recurring_no_end_date"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.end_date IS NOT NULL THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans_unfiltered
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships cannot have an end_date'
                USING CONSTRAINT = 'recurring_no_end_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_recurring_no_end_date"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_recurring_no_overlapping_daterange"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships_unfiltered mm
            WHERE mm.crm_user_id = NEW.crm_user_id
              AND mm.gym_id = NEW.gym_id
              AND mm.plan_id = NEW.plan_id
              AND mm.item_id <> NEW.item_id
              AND daterange(mm.start_date, mm.cancel_date, '[)')
               && daterange(NEW.start_date, NEW.cancel_date, '[)')
        ) THEN
            RAISE EXCEPTION 'recurring membership overlaps an existing membership on the same plan'
                USING CONSTRAINT = 'recurring_no_overlapping_daterange';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_recurring_no_overlapping_daterange"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_linked_account_hierarchy"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."enforce_linked_account_hierarchy"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_linked_discount_sequence"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    max_num INTEGER;
    total_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts_unfiltered
        WHERE gym_id = NEW.gym_id
          AND membership_plan_id = NEW.membership_plan_id
          AND discount_type = 'linked';

        IF NEW.linked_discount_num <> max_num + 1 THEN
            RAISE EXCEPTION 'linked_discount_num must be % (next sequential), got %',
                max_num + 1, NEW.linked_discount_num;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.linked_discount_num IS DISTINCT FROM OLD.linked_discount_num THEN
            SELECT COUNT(*) INTO total_count
            FROM gym_discounts_unfiltered
            WHERE gym_id = NEW.gym_id
              AND membership_plan_id = NEW.membership_plan_id
              AND discount_type = 'linked'
              AND discount_id <> NEW.discount_id;

            IF NEW.linked_discount_num < 1 OR NEW.linked_discount_num > total_count + 1 THEN
                RAISE EXCEPTION 'linked_discount_num out of range [1..%]', total_count + 1;
            END IF;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts_unfiltered
        WHERE gym_id = OLD.gym_id
          AND membership_plan_id = OLD.membership_plan_id
          AND discount_type = 'linked';

        IF OLD.linked_discount_num <> max_num THEN
            RAISE EXCEPTION 'Can only delete the highest linked_discount_num (%). Got %',
                max_num, OLD.linked_discount_num;
        END IF;
        RETURN OLD;
    END IF;
END;
$$;


ALTER FUNCTION "public"."enforce_linked_discount_sequence"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gym_has_owner"("p_gym_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.employee_type = 'owner'
    );
$$;


ALTER FUNCTION "public"."gym_has_owner"("p_gym_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_gym_admin_or_owner"("p_gym_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
        AND gym_employees.employee_type IN ('owner', 'admin')
    );
$$;


ALTER FUNCTION "public"."is_gym_admin_or_owner"("p_gym_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_gym_employee"("p_gym_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
    );
$$;


ALTER FUNCTION "public"."is_gym_employee"("p_gym_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_cancel_date_overwrite"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF OLD.cancel_date IS NOT NULL AND NEW.cancel_date IS DISTINCT FROM OLD.cancel_date THEN
        RAISE EXCEPTION 'cancel_date cannot be changed once set'
            USING CONSTRAINT = 'cancel_date_immutable';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_cancel_date_overwrite"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_plan_id_overwrite"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
        RAISE EXCEPTION 'plan_id cannot be changed after creation'
            USING CONSTRAINT = 'plan_id_immutable';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_plan_id_overwrite"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_stripe_customer_id_overwrite"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_stripe_customer_id_overwrite"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_stripe_item_id_overwrite"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF OLD.stripe_item_id IS NOT NULL AND NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_stripe_item_id_overwrite"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_user_id_overwrite"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_user_id_overwrite"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."gym_class_exceptions" (
    "exception_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "schedule_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "original_date" "date" NOT NULL,
    "is_cancelled" boolean,
    "new_class_time" time without time zone,
    "new_duration_minutes" integer,
    "new_max_capacity" integer,
    "new_instructor_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gym_class_exceptions_new_duration_minutes_check" CHECK (("new_duration_minutes" > 0)),
    CONSTRAINT "gym_class_exceptions_new_max_capacity_check" CHECK (("new_max_capacity" > 0))
);


ALTER TABLE "public"."gym_class_exceptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_class_schedules" (
    "schedule_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "class_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "class_time" time without time zone NOT NULL,
    "duration_minutes" integer NOT NULL,
    "recurring_unit" character varying NOT NULL,
    "recurring_interval" integer DEFAULT 1 NOT NULL,
    "sun" boolean DEFAULT false NOT NULL,
    "mon" boolean DEFAULT false NOT NULL,
    "tue" boolean DEFAULT false NOT NULL,
    "wed" boolean DEFAULT false NOT NULL,
    "thu" boolean DEFAULT false NOT NULL,
    "fri" boolean DEFAULT false NOT NULL,
    "sat" boolean DEFAULT false NOT NULL,
    "sun_instructor_id" "uuid",
    "mon_instructor_id" "uuid",
    "tue_instructor_id" "uuid",
    "wed_instructor_id" "uuid",
    "thu_instructor_id" "uuid",
    "fri_instructor_id" "uuid",
    "sat_instructor_id" "uuid",
    "is_cancelled" boolean DEFAULT false NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gym_class_schedules_check" CHECK ((("end_date" IS NULL) OR ("end_date" >= "start_date"))),
    CONSTRAINT "gym_class_schedules_check1" CHECK (((("recurring_unit")::"text" <> 'weekly'::"text") OR "sun" OR "mon" OR "tue" OR "wed" OR "thu" OR "fri" OR "sat")),
    CONSTRAINT "gym_class_schedules_duration_minutes_check" CHECK (("duration_minutes" > 0)),
    CONSTRAINT "gym_class_schedules_recurring_interval_check" CHECK (("recurring_interval" > 0)),
    CONSTRAINT "gym_class_schedules_recurring_unit_check" CHECK ((("recurring_unit")::"text" = ANY (ARRAY[('daily'::character varying)::"text", ('weekly'::character varying)::"text", ('monthly'::character varying)::"text"])))
);


ALTER TABLE "public"."gym_class_schedules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_classes" (
    "class_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "class_name" character varying NOT NULL,
    "class_description" character varying,
    "allowed_plan_ids" "jsonb",
    "max_capacity" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "end_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gym_classes_class_name_check" CHECK ((("class_name")::"text" <> ''::"text")),
    CONSTRAINT "gym_classes_max_capacity_check" CHECK (("max_capacity" > 0))
);


ALTER TABLE "public"."gym_classes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_classes_log" (
    "log_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "crm_user_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "class_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "instructor_id" "uuid",
    "time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "item_id" "uuid" NOT NULL
);


ALTER TABLE "public"."gym_classes_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_discounts_unfiltered" (
    "discount_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "discount_name" character varying NOT NULL,
    "discount_type" character varying NOT NULL,
    "percentage_off" double precision,
    "dollar_off" integer,
    "membership_plan_id" "uuid",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "stripe_coupon_id" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "duration" character varying NOT NULL,
    "duration_in_months" integer,
    "linked_discount_num" integer,
    CONSTRAINT "chk_duration_in_months" CHECK ((((("duration")::"text" = 'repeating'::"text") AND ("duration_in_months" IS NOT NULL)) OR ((("duration")::"text" <> 'repeating'::"text") AND ("duration_in_months" IS NULL)))),
    CONSTRAINT "chk_linked_discount_fields" CHECK ((((("discount_type")::"text" = 'linked'::"text") AND ("membership_plan_id" IS NOT NULL) AND ("linked_discount_num" IS NOT NULL) AND ("dollar_off" IS NOT NULL)) OR ((("discount_type")::"text" <> 'linked'::"text") AND ("membership_plan_id" IS NULL) AND ("linked_discount_num" IS NULL)))),
    CONSTRAINT "gym_discounts_unfiltered_check" CHECK (("num_nonnulls"("percentage_off", "dollar_off") = 1)),
    CONSTRAINT "gym_discounts_unfiltered_discount_name_check" CHECK ((("discount_name")::"text" <> ''::"text")),
    CONSTRAINT "gym_discounts_unfiltered_discount_type_check" CHECK ((("discount_type")::"text" = ANY (ARRAY[('preset'::character varying)::"text", ('custom'::character varying)::"text", ('linked'::character varying)::"text"]))),
    CONSTRAINT "gym_discounts_unfiltered_dollar_off_check" CHECK (("dollar_off" > 0)),
    CONSTRAINT "gym_discounts_unfiltered_duration_check" CHECK ((("duration")::"text" = ANY (ARRAY[('once'::character varying)::"text", ('repeating'::character varying)::"text", ('forever'::character varying)::"text"]))),
    CONSTRAINT "gym_discounts_unfiltered_duration_in_months_check" CHECK (("duration_in_months" > 0)),
    CONSTRAINT "gym_discounts_unfiltered_linked_discount_num_check" CHECK (("linked_discount_num" > 0)),
    CONSTRAINT "gym_discounts_unfiltered_percentage_off_check" CHECK ((("percentage_off" > (0)::double precision) AND ("percentage_off" <= (100)::double precision)))
);


ALTER TABLE "public"."gym_discounts_unfiltered" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gym_discounts" WITH ("security_invoker"='true') AS
 SELECT "discount_id",
    "gym_id",
    "discount_name",
    "discount_type",
    "percentage_off",
    "dollar_off",
    "membership_plan_id",
    "linked_discount_num",
    "duration",
    "duration_in_months",
    "is_deleted",
    "stripe_coupon_id",
    "created_at"
   FROM "public"."gym_discounts_unfiltered"
  WHERE ("stripe_coupon_id" IS NOT NULL);


ALTER VIEW "public"."gym_discounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_employees" (
    "employee_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "gym_id" "uuid" NOT NULL,
    "employee_type" character varying NOT NULL,
    "first_name" character varying NOT NULL,
    "last_name" character varying NOT NULL,
    "phone" character varying,
    "email" character varying,
    "employee_pic_url" character varying,
    "employee_public_description" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gym_employees_employee_type_check" CHECK ((("employee_type")::"text" = ANY (ARRAY[('owner'::character varying)::"text", ('admin'::character varying)::"text", ('trainer'::character varying)::"text"]))),
    CONSTRAINT "gym_employees_first_name_check" CHECK ((("first_name")::"text" <> ''::"text")),
    CONSTRAINT "gym_employees_last_name_check" CHECK ((("last_name")::"text" <> ''::"text"))
);


ALTER TABLE "public"."gym_employees" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_history" (
    "gym_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "members_total" integer NOT NULL,
    "members_churned" integer NOT NULL,
    "members_gained" integer NOT NULL,
    "members_retained" integer NOT NULL,
    "revenue" integer NOT NULL,
    CONSTRAINT "gym_history_members_churned_check" CHECK (("members_churned" >= 0)),
    CONSTRAINT "gym_history_members_gained_check" CHECK (("members_gained" >= 0)),
    CONSTRAINT "gym_history_members_retained_check" CHECK (("members_retained" >= 0)),
    CONSTRAINT "gym_history_members_total_check" CHECK (("members_total" >= 0)),
    CONSTRAINT "gym_history_revenue_check" CHECK (("revenue" >= 0))
);


ALTER TABLE "public"."gym_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gym_rewards" (
    "reward_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "title" character varying NOT NULL,
    "amount_off" character varying,
    "image_url" character varying,
    "point_cost" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gym_rewards_point_cost_check" CHECK (("point_cost" > 0)),
    CONSTRAINT "gym_rewards_title_check" CHECK ((("title")::"text" <> ''::"text"))
);


ALTER TABLE "public"."gym_rewards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gyms" (
    "gym_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_name" character varying NOT NULL,
    "gym_description" character varying,
    "stripe_account_id" character varying,
    "stripe_onboarding_status" character varying DEFAULT 'not_started'::character varying NOT NULL,
    "timezone" "text" DEFAULT 'America/Chicago'::"text" NOT NULL,
    CONSTRAINT "gyms_gym_name_check" CHECK ((("gym_name")::"text" <> ''::"text")),
    CONSTRAINT "gyms_stripe_onboarding_status_check" CHECK ((("stripe_onboarding_status")::"text" = ANY (ARRAY[('not_started'::character varying)::"text", ('pending'::character varying)::"text", ('complete'::character varying)::"text", ('disabled'::character varying)::"text"]))),
    CONSTRAINT "gyms_timezone_valid" CHECK ((("now"() AT TIME ZONE "timezone") IS NOT NULL))
);


ALTER TABLE "public"."gyms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."member_memberships_unfiltered" (
    "crm_user_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "price_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "cancel_date" "date",
    "last_paid_date" "date",
    "next_due_date" "date",
    "discount_ids" "jsonb",
    "total_price" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "item_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "prorate" boolean DEFAULT true NOT NULL,
    "stripe_item_id" character varying,
    CONSTRAINT "member_memberships_unfiltered_total_price_check" CHECK (("total_price" >= 0))
);


ALTER TABLE "public"."member_memberships_unfiltered" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."member_memberships" WITH ("security_invoker"='true') AS
 SELECT "item_id",
    "crm_user_id",
    "gym_id",
    "plan_id",
    "price_id",
    "start_date",
    "end_date",
    "cancel_date",
    "last_paid_date",
    "next_due_date",
    "discount_ids",
    "stripe_item_id",
    "prorate",
    "total_price",
    "created_at"
   FROM "public"."member_memberships_unfiltered"
  WHERE ("stripe_item_id" IS NOT NULL);


ALTER VIEW "public"."member_memberships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_profiles_unfiltered" (
    "crm_user_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "gym_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_class" timestamp with time zone,
    "first_name" character varying NOT NULL,
    "last_name" character varying NOT NULL,
    "photo_url" character varying,
    "phone" character varying,
    "email" character varying,
    "address" character varying,
    "emergency_contact_name" character varying,
    "emergency_contact_phone" character varying,
    "emergency_contact_email" character varying,
    "points_balance" integer DEFAULT 0 NOT NULL,
    "account_linked_to_id" "uuid",
    "stripe_customer_id" character varying,
    "stripe_payment_method_id" character varying,
    "payment_type" character varying,
    "card_brand" character varying,
    "card_last_four" character varying(4),
    "card_exp_month" integer,
    "card_exp_year" integer,
    "stripe_sub_id_month" character varying,
    "freeze_end_date" "date",
    "freeze_start_date" "date",
    "linked_discount_id" "uuid",
    "total_monthly_recurring_price" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "freeze_dates_must_be_paired" CHECK (((("freeze_start_date" IS NULL) AND ("freeze_end_date" IS NULL)) OR (("freeze_start_date" IS NOT NULL) AND ("freeze_end_date" IS NOT NULL)))),
    CONSTRAINT "linked_account_no_stripe" CHECK ((("account_linked_to_id" IS NULL) OR (("stripe_sub_id_month" IS NULL) AND ("freeze_start_date" IS NULL) AND ("freeze_end_date" IS NULL) AND ("payment_type" IS NULL) AND ("card_brand" IS NULL) AND ("card_last_four" IS NULL) AND ("card_exp_month" IS NULL) AND ("card_exp_year" IS NULL)))),
    CONSTRAINT "user_gym_profiles_unfiltered_first_name_check" CHECK ((("first_name")::"text" <> ''::"text")),
    CONSTRAINT "user_gym_profiles_unfiltered_last_name_check" CHECK ((("last_name")::"text" <> ''::"text")),
    CONSTRAINT "user_gym_profiles_unfiltered_points_balance_check" CHECK (("points_balance" >= 0)),
    CONSTRAINT "user_gym_profiles_unfiltered_total_monthly_recurring_pric_check" CHECK (("total_monthly_recurring_price" >= 0))
);


ALTER TABLE "public"."user_gym_profiles_unfiltered" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."member_memberships_status" WITH ("security_invoker"='true') AS
 SELECT "mm"."item_id",
    "mm"."crm_user_id",
    "mm"."gym_id",
    "mm"."plan_id",
    "mm"."price_id",
    "mm"."start_date",
    "mm"."end_date",
    "mm"."cancel_date",
    "mm"."last_paid_date",
    "mm"."next_due_date",
    "mm"."discount_ids",
    "mm"."stripe_item_id",
    "mm"."prorate",
    "mm"."total_price",
    "mm"."created_at",
    "freeze_owner"."freeze_start_date",
    "freeze_owner"."freeze_end_date",
        CASE
            WHEN (("mm"."cancel_date" IS NOT NULL) AND ("mm"."cancel_date" <= (("now"() AT TIME ZONE "g"."timezone"))::"date")) THEN 'cancelled'::"text"
            WHEN (("mm"."end_date" IS NOT NULL) AND ("mm"."end_date" <= (("now"() AT TIME ZONE "g"."timezone"))::"date")) THEN 'ended'::"text"
            WHEN (("freeze_owner"."freeze_start_date" IS NOT NULL) AND ("freeze_owner"."freeze_end_date" IS NOT NULL) AND ("freeze_owner"."freeze_start_date" <= (("now"() AT TIME ZONE "g"."timezone"))::"date") AND ((("now"() AT TIME ZONE "g"."timezone"))::"date" <= "freeze_owner"."freeze_end_date")) THEN 'frozen'::"text"
            ELSE 'active'::"text"
        END AS "status"
   FROM ((("public"."member_memberships" "mm"
     JOIN "public"."gyms" "g" ON (("g"."gym_id" = "mm"."gym_id")))
     JOIN "public"."user_gym_profiles_unfiltered" "ugp" ON (("ugp"."crm_user_id" = "mm"."crm_user_id")))
     JOIN "public"."user_gym_profiles_unfiltered" "freeze_owner" ON (("freeze_owner"."crm_user_id" = COALESCE("ugp"."account_linked_to_id", "ugp"."crm_user_id"))));


ALTER VIEW "public"."member_memberships_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."membership_plan_prices_unfiltered" (
    "price_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "stripe_price_id" character varying,
    "price" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "membership_plan_prices_unfiltered_price_check" CHECK (("price" >= 0))
);


ALTER TABLE "public"."membership_plan_prices_unfiltered" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."membership_plan_prices" WITH ("security_invoker"='true') AS
 SELECT "price_id",
    "plan_id",
    "gym_id",
    "stripe_price_id",
    "price",
    "is_active",
    "created_at"
   FROM "public"."membership_plan_prices_unfiltered"
  WHERE ("stripe_price_id" IS NOT NULL);


ALTER VIEW "public"."membership_plan_prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."membership_plans_unfiltered" (
    "plan_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "plan_name" character varying NOT NULL,
    "plan_type" character varying NOT NULL,
    "class_count" integer,
    "duration_amount" integer,
    "duration_unit" character varying,
    "is_public" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "stripe_product_id" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "duration_both_or_neither" CHECK ((("duration_amount" IS NULL) = ("duration_unit" IS NULL))),
    CONSTRAINT "duration_required_unless_class_count" CHECK (((("duration_amount" IS NOT NULL) AND ("duration_unit" IS NOT NULL)) OR ((("plan_type")::"text" <> 'recurring'::"text") AND ("class_count" IS NOT NULL)))),
    CONSTRAINT "membership_plans_unfiltered_class_count_check" CHECK (("class_count" > 0)),
    CONSTRAINT "membership_plans_unfiltered_duration_amount_check" CHECK (("duration_amount" > 0)),
    CONSTRAINT "membership_plans_unfiltered_duration_unit_check" CHECK ((("duration_unit")::"text" = ANY (ARRAY[('week'::character varying)::"text", ('month'::character varying)::"text", ('year'::character varying)::"text"]))),
    CONSTRAINT "membership_plans_unfiltered_plan_name_check" CHECK ((("plan_name")::"text" <> ''::"text")),
    CONSTRAINT "membership_plans_unfiltered_plan_type_check" CHECK ((("plan_type")::"text" = ANY (ARRAY[('trial'::character varying)::"text", ('recurring'::character varying)::"text", ('one_time'::character varying)::"text"]))),
    CONSTRAINT "recurring_must_be_monthly" CHECK (((("plan_type")::"text" <> 'recurring'::"text") OR ((("duration_unit")::"text" = 'month'::"text") AND ("duration_amount" = 1))))
);


ALTER TABLE "public"."membership_plans_unfiltered" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."membership_plans" WITH ("security_invoker"='true') AS
 SELECT "plan_id",
    "gym_id",
    "plan_name",
    "plan_type",
    "class_count",
    "duration_amount",
    "duration_unit",
    "is_public",
    "is_deleted",
    "stripe_product_id",
    "created_at"
   FROM "public"."membership_plans_unfiltered"
  WHERE ("stripe_product_id" IS NOT NULL);


ALTER VIEW "public"."membership_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stripe_webhook_events" (
    "event_id" character varying NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "event_type" character varying NOT NULL,
    "processed_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."stripe_webhook_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_activities" (
    "activity_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "activity_type" character varying NOT NULL,
    "activity_info" "jsonb" DEFAULT '{}'::"jsonb",
    "time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "crm_user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."user_activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_charges" (
    "charge_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "crm_user_id" "uuid" NOT NULL,
    "kind" "public"."charge_kind" NOT NULL,
    "status" "public"."charge_status" NOT NULL,
    "amount" integer NOT NULL,
    "currency" character(3) DEFAULT 'usd'::"bpchar" NOT NULL,
    "payment_method_type" character varying,
    "stripe_charge_id" character varying,
    "stripe_refund_id" character varying,
    "refunds_charge_id" "uuid",
    "charge_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stripe_event_payload" "jsonb",
    CONSTRAINT "payment_amount_nonneg" CHECK ((("kind" <> 'payment'::"public"."charge_kind") OR ("amount" >= 0))),
    CONSTRAINT "payment_has_charge_id" CHECK ((("kind" <> 'payment'::"public"."charge_kind") OR ("stripe_charge_id" IS NOT NULL) OR (("payment_method_type")::"text" = 'cash'::"text"))),
    CONSTRAINT "payment_has_no_parent" CHECK ((("kind" <> 'payment'::"public"."charge_kind") OR ("refunds_charge_id" IS NULL))),
    CONSTRAINT "payment_has_no_refund_id" CHECK ((("kind" <> 'payment'::"public"."charge_kind") OR ("stripe_refund_id" IS NULL))),
    CONSTRAINT "refund_amount_nonpos" CHECK ((("kind" <> 'refund'::"public"."charge_kind") OR ("amount" <= 0))),
    CONSTRAINT "refund_has_no_charge_id" CHECK ((("kind" <> 'refund'::"public"."charge_kind") OR ("stripe_charge_id" IS NULL))),
    CONSTRAINT "refund_has_parent" CHECK ((("kind" <> 'refund'::"public"."charge_kind") OR ("refunds_charge_id" IS NOT NULL))),
    CONSTRAINT "refund_has_refund_id" CHECK ((("kind" <> 'refund'::"public"."charge_kind") OR ("stripe_refund_id" IS NOT NULL)))
);


ALTER TABLE "public"."user_gym_charges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_invoice_applied_discounts" (
    "applied_discount_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "discount_id" "uuid" NOT NULL,
    "amount_off" integer NOT NULL,
    "stripe_coupon_id" character varying,
    CONSTRAINT "user_gym_invoice_applied_discounts_amount_off_check" CHECK (("amount_off" >= 0))
);


ALTER TABLE "public"."user_gym_invoice_applied_discounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_invoice_line_items" (
    "line_item_id" character varying NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "item_type" "public"."line_item_type" NOT NULL,
    "name" character varying NOT NULL,
    "amount" integer NOT NULL,
    "stripe_product_id" character varying,
    "item_id" "uuid",
    CONSTRAINT "custom_line_has_no_item_id" CHECK ((("item_type" <> 'custom'::"public"."line_item_type") OR ("item_id" IS NULL))),
    CONSTRAINT "membership_line_has_item_id" CHECK ((("item_type" <> 'membership'::"public"."line_item_type") OR ("item_id" IS NOT NULL))),
    CONSTRAINT "user_gym_invoice_line_items_amount_check" CHECK (("amount" >= 0)),
    CONSTRAINT "user_gym_invoice_line_items_name_check" CHECK ((("name")::"text" <> ''::"text"))
);


ALTER TABLE "public"."user_gym_invoice_line_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_invoices" (
    "invoice_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "crm_user_id" "uuid" NOT NULL,
    "status" "public"."invoice_status" DEFAULT 'open'::"public"."invoice_status" NOT NULL,
    "total_amount" integer NOT NULL,
    "currency" character(3) DEFAULT 'usd'::"bpchar" NOT NULL,
    "stripe_invoice_id" character varying,
    "stripe_payment_intent_id" character varying,
    "invoice_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stripe_event_payload" "jsonb",
    CONSTRAINT "user_gym_invoices_total_amount_check" CHECK (("total_amount" >= 0))
);


ALTER TABLE "public"."user_gym_invoices" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."user_gym_profiles" WITH ("security_invoker"='true') AS
 SELECT "crm_user_id",
    "user_id",
    "gym_id",
    "created_at",
    "last_class",
    "first_name",
    "last_name",
    "photo_url",
    "phone",
    "email",
    "address",
    "emergency_contact_name",
    "emergency_contact_phone",
    "emergency_contact_email",
    "points_balance",
    "freeze_start_date",
    "freeze_end_date",
    "account_linked_to_id",
    "linked_discount_id",
    "stripe_customer_id",
    "stripe_sub_id_month",
    "stripe_payment_method_id",
    "payment_type",
    "card_brand",
    "card_last_four",
    "card_exp_month",
    "card_exp_year",
    "total_monthly_recurring_price"
   FROM "public"."user_gym_profiles_unfiltered"
  WHERE ("stripe_customer_id" IS NOT NULL);


ALTER VIEW "public"."user_gym_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_gym_reward_redemptions" (
    "redemption_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gym_id" "uuid" NOT NULL,
    "crm_user_id" "uuid" NOT NULL,
    "reward_id" "uuid" NOT NULL,
    "point_cost" integer NOT NULL,
    "redeemed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_gym_reward_redemptions_point_cost_check" CHECK (("point_cost" >= 0))
);


ALTER TABLE "public"."user_gym_reward_redemptions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "gym_class_exceptions_pkey" PRIMARY KEY ("exception_id");



ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "gym_class_exceptions_schedule_id_original_date_key" UNIQUE ("schedule_id", "original_date");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "gym_class_schedules_class_id_daterange_excl" EXCLUDE USING "gist" ("class_id" WITH =, "daterange"("start_date", "end_date", '[]'::"text") WITH &&);



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "gym_class_schedules_pkey" PRIMARY KEY ("schedule_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "gym_class_schedules_schedule_id_gym_id_key" UNIQUE ("schedule_id", "gym_id");



ALTER TABLE ONLY "public"."gym_classes"
    ADD CONSTRAINT "gym_classes_class_id_gym_id_key" UNIQUE ("class_id", "gym_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "gym_classes_log_pkey" PRIMARY KEY ("log_id");



ALTER TABLE ONLY "public"."gym_classes"
    ADD CONSTRAINT "gym_classes_pkey" PRIMARY KEY ("class_id");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "gym_discounts_unfiltered_discount_id_gym_id_key" UNIQUE ("discount_id", "gym_id");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key" UNIQUE ("gym_id", "membership_plan_id", "linked_discount_num");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "gym_discounts_unfiltered_pkey" PRIMARY KEY ("discount_id");



ALTER TABLE ONLY "public"."gym_employees"
    ADD CONSTRAINT "gym_employees_employee_id_gym_id_key" UNIQUE ("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_employees"
    ADD CONSTRAINT "gym_employees_pkey" PRIMARY KEY ("employee_id");



ALTER TABLE ONLY "public"."gym_employees"
    ADD CONSTRAINT "gym_employees_user_id_gym_id_key" UNIQUE ("user_id", "gym_id");



ALTER TABLE ONLY "public"."gym_history"
    ADD CONSTRAINT "gym_history_pkey" PRIMARY KEY ("gym_id", "date");



ALTER TABLE ONLY "public"."gym_rewards"
    ADD CONSTRAINT "gym_rewards_pkey" PRIMARY KEY ("reward_id");



ALTER TABLE ONLY "public"."gym_rewards"
    ADD CONSTRAINT "gym_rewards_reward_id_gym_id_key" UNIQUE ("reward_id", "gym_id");



ALTER TABLE ONLY "public"."gyms"
    ADD CONSTRAINT "gyms_pkey" PRIMARY KEY ("gym_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "member_memberships_unfiltered_item_id_crm_user_id_key" UNIQUE ("item_id", "crm_user_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "member_memberships_unfiltered_item_id_gym_id_key" UNIQUE ("item_id", "gym_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "member_memberships_unfiltered_pkey" PRIMARY KEY ("item_id");



ALTER TABLE ONLY "public"."membership_plan_prices_unfiltered"
    ADD CONSTRAINT "membership_plan_prices_unfiltered_pkey" PRIMARY KEY ("price_id");



ALTER TABLE ONLY "public"."membership_plan_prices_unfiltered"
    ADD CONSTRAINT "membership_plan_prices_unfiltered_price_id_plan_id_key" UNIQUE ("price_id", "plan_id");



ALTER TABLE ONLY "public"."membership_plans_unfiltered"
    ADD CONSTRAINT "membership_plans_unfiltered_pkey" PRIMARY KEY ("plan_id");



ALTER TABLE ONLY "public"."membership_plans_unfiltered"
    ADD CONSTRAINT "membership_plans_unfiltered_plan_id_gym_id_key" UNIQUE ("plan_id", "gym_id");



ALTER TABLE ONLY "public"."stripe_webhook_events"
    ADD CONSTRAINT "stripe_webhook_events_pkey" PRIMARY KEY ("event_id");



ALTER TABLE ONLY "public"."user_activities"
    ADD CONSTRAINT "user_activities_pkey" PRIMARY KEY ("activity_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "user_gym_charges_pkey" PRIMARY KEY ("charge_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "user_gym_charges_stripe_charge_id_key" UNIQUE ("stripe_charge_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "user_gym_charges_stripe_refund_id_key" UNIQUE ("stripe_refund_id");



ALTER TABLE ONLY "public"."user_gym_invoice_applied_discounts"
    ADD CONSTRAINT "user_gym_invoice_applied_discounts_pkey" PRIMARY KEY ("applied_discount_id");



ALTER TABLE ONLY "public"."user_gym_invoice_line_items"
    ADD CONSTRAINT "user_gym_invoice_line_items_pkey" PRIMARY KEY ("line_item_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "user_gym_invoices_invoice_id_gym_id_key" UNIQUE ("invoice_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "user_gym_invoices_pkey" PRIMARY KEY ("invoice_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "user_gym_invoices_stripe_invoice_id_key" UNIQUE ("stripe_invoice_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "user_gym_invoices_stripe_payment_intent_id_key" UNIQUE ("stripe_payment_intent_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "user_gym_profiles_unfiltered_crm_user_id_gym_id_key" UNIQUE ("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "user_gym_profiles_unfiltered_pkey" PRIMARY KEY ("crm_user_id");



ALTER TABLE ONLY "public"."user_gym_reward_redemptions"
    ADD CONSTRAINT "user_gym_reward_redemptions_pkey" PRIMARY KEY ("redemption_id");



CREATE INDEX "idx_applied_discounts_invoice" ON "public"."user_gym_invoice_applied_discounts" USING "btree" ("invoice_id");



CREATE INDEX "idx_charges_gym_time" ON "public"."user_gym_charges" USING "btree" ("gym_id", "charge_time" DESC);



CREATE INDEX "idx_charges_invoice" ON "public"."user_gym_charges" USING "btree" ("invoice_id");



CREATE INDEX "idx_charges_user_gym_time" ON "public"."user_gym_charges" USING "btree" ("crm_user_id", "gym_id", "charge_time" DESC);



CREATE INDEX "idx_invoices_gym_time" ON "public"."user_gym_invoices" USING "btree" ("gym_id", "invoice_time" DESC);



CREATE INDEX "idx_invoices_user_gym_time" ON "public"."user_gym_invoices" USING "btree" ("crm_user_id", "gym_id", "invoice_time" DESC);



CREATE INDEX "idx_line_items_invoice" ON "public"."user_gym_invoice_line_items" USING "btree" ("invoice_id");



CREATE INDEX "idx_line_items_item" ON "public"."user_gym_invoice_line_items" USING "btree" ("item_id") WHERE ("item_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_max_one_active_price_per_plan" ON "public"."membership_plan_prices_unfiltered" USING "btree" ("plan_id") WHERE ("is_active" = true);



CREATE UNIQUE INDEX "idx_profiles_stripe_customer" ON "public"."user_gym_profiles_unfiltered" USING "btree" ("stripe_customer_id");



CREATE INDEX "idx_reward_redemptions_user_gym_time" ON "public"."user_gym_reward_redemptions" USING "btree" ("crm_user_id", "gym_id", "redeemed_at" DESC);



CREATE INDEX "idx_webhook_events_gym" ON "public"."stripe_webhook_events" USING "btree" ("gym_id", "processed_at" DESC);



CREATE UNIQUE INDEX "unique_employee_user_gym" ON "public"."gym_employees" USING "btree" ("user_id", "gym_id") WHERE ("user_id" IS NOT NULL);



CREATE UNIQUE INDEX "unique_user_gym" ON "public"."user_gym_profiles_unfiltered" USING "btree" ("user_id", "gym_id") WHERE ("user_id" IS NOT NULL);



CREATE OR REPLACE TRIGGER "trg_check_class_plan_ids_gym_match" BEFORE INSERT OR UPDATE OF "allowed_plan_ids" ON "public"."gym_classes" FOR EACH ROW EXECUTE FUNCTION "public"."check_class_plan_ids_gym_match"();



CREATE OR REPLACE TRIGGER "trg_check_discount_ids_gym_match" BEFORE INSERT OR UPDATE OF "discount_ids" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_discount_ids_gym_match"();



CREATE OR REPLACE TRIGGER "trg_check_linked_discount_type" BEFORE INSERT OR UPDATE OF "linked_discount_id" ON "public"."user_gym_profiles_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_linked_discount_type"();



CREATE OR REPLACE TRIGGER "trg_enforce_linked_account_hierarchy" BEFORE INSERT OR UPDATE OF "account_linked_to_id" ON "public"."user_gym_profiles_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_linked_account_hierarchy"();



CREATE OR REPLACE TRIGGER "trg_enforce_linked_discount_sequence_delete" BEFORE DELETE ON "public"."gym_discounts_unfiltered" FOR EACH ROW WHEN ((("old"."discount_type")::"text" = 'linked'::"text")) EXECUTE FUNCTION "public"."enforce_linked_discount_sequence"();



CREATE OR REPLACE TRIGGER "trg_enforce_linked_discount_sequence_insert_update" BEFORE INSERT OR UPDATE OF "linked_discount_num" ON "public"."gym_discounts_unfiltered" FOR EACH ROW WHEN ((("new"."discount_type")::"text" = 'linked'::"text")) EXECUTE FUNCTION "public"."enforce_linked_discount_sequence"();



CREATE OR REPLACE TRIGGER "trg_enforce_no_schedule_gaps" AFTER INSERT OR DELETE OR UPDATE ON "public"."gym_class_schedules" FOR EACH ROW EXECUTE FUNCTION "public"."check_no_schedule_gaps"();



CREATE OR REPLACE TRIGGER "trg_prevent_cancel_date_overwrite" BEFORE UPDATE OF "cancel_date" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_cancel_date_overwrite"();



CREATE OR REPLACE TRIGGER "trg_prevent_plan_id_overwrite" BEFORE UPDATE OF "plan_id" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_plan_id_overwrite"();



CREATE OR REPLACE TRIGGER "trg_prevent_stripe_customer_id_overwrite" BEFORE UPDATE OF "stripe_customer_id" ON "public"."user_gym_profiles_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_stripe_customer_id_overwrite"();



CREATE OR REPLACE TRIGGER "trg_prevent_stripe_item_id_overwrite" BEFORE UPDATE OF "stripe_item_id" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_stripe_item_id_overwrite"();



CREATE OR REPLACE TRIGGER "trg_prevent_user_id_overwrite" BEFORE UPDATE OF "user_id" ON "public"."user_gym_profiles_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_user_id_overwrite"();



CREATE OR REPLACE TRIGGER "trg_recurring_chronological_start_date" BEFORE INSERT ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_recurring_chronological_start_date"();



CREATE OR REPLACE TRIGGER "trg_recurring_no_active_memberships" BEFORE INSERT ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_recurring_no_active_memberships"();



CREATE OR REPLACE TRIGGER "trg_recurring_no_end_date" BEFORE INSERT OR UPDATE OF "end_date" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_recurring_no_end_date"();



CREATE OR REPLACE TRIGGER "trg_recurring_no_overlapping_daterange" BEFORE INSERT OR UPDATE OF "cancel_date" ON "public"."member_memberships_unfiltered" FOR EACH ROW EXECUTE FUNCTION "public"."check_recurring_no_overlapping_daterange"();



ALTER TABLE ONLY "public"."user_activities"
    ADD CONSTRAINT "fk_activity_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_activities"
    ADD CONSTRAINT "fk_activity_profile_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_applied_discounts"
    ADD CONSTRAINT "fk_applied_discount_discount_gym" FOREIGN KEY ("discount_id", "gym_id") REFERENCES "public"."gym_discounts_unfiltered"("discount_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_applied_discounts"
    ADD CONSTRAINT "fk_applied_discount_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_applied_discounts"
    ADD CONSTRAINT "fk_applied_discount_invoice" FOREIGN KEY ("invoice_id") REFERENCES "public"."user_gym_invoices"("invoice_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_gym_invoice_applied_discounts"
    ADD CONSTRAINT "fk_applied_discount_invoice_gym" FOREIGN KEY ("invoice_id", "gym_id") REFERENCES "public"."user_gym_invoices"("invoice_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "fk_charge_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "fk_charge_invoice" FOREIGN KEY ("invoice_id") REFERENCES "public"."user_gym_invoices"("invoice_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "fk_charge_invoice_gym" FOREIGN KEY ("invoice_id", "gym_id") REFERENCES "public"."user_gym_invoices"("invoice_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "fk_charge_user_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."gym_classes"
    ADD CONSTRAINT "fk_class_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_class" FOREIGN KEY ("class_id", "gym_id") REFERENCES "public"."gym_classes"("class_id", "gym_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_class_id" FOREIGN KEY ("class_id") REFERENCES "public"."gym_classes"("class_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_instructor" FOREIGN KEY ("instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_membership_item" FOREIGN KEY ("item_id", "crm_user_id") REFERENCES "public"."member_memberships_unfiltered"("item_id", "crm_user_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_plan_id" FOREIGN KEY ("plan_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id");



ALTER TABLE ONLY "public"."gym_classes_log"
    ADD CONSTRAINT "fk_class_log_profile_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "fk_discount_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "fk_discount_plan" FOREIGN KEY ("membership_plan_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id");



ALTER TABLE ONLY "public"."gym_discounts_unfiltered"
    ADD CONSTRAINT "fk_discount_plan_gym" FOREIGN KEY ("membership_plan_id", "gym_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id", "gym_id");



ALTER TABLE ONLY "public"."gym_employees"
    ADD CONSTRAINT "fk_employee_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_employees"
    ADD CONSTRAINT "fk_employee_user" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "fk_exception_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "fk_exception_instructor" FOREIGN KEY ("new_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "fk_exception_schedule" FOREIGN KEY ("schedule_id", "gym_id") REFERENCES "public"."gym_class_schedules"("schedule_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_exceptions"
    ADD CONSTRAINT "fk_exception_schedule_id" FOREIGN KEY ("schedule_id") REFERENCES "public"."gym_class_schedules"("schedule_id");



ALTER TABLE ONLY "public"."gym_history"
    ADD CONSTRAINT "fk_history_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "fk_invoice_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_invoices"
    ADD CONSTRAINT "fk_invoice_user_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_line_items"
    ADD CONSTRAINT "fk_line_item_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_line_items"
    ADD CONSTRAINT "fk_line_item_invoice" FOREIGN KEY ("invoice_id") REFERENCES "public"."user_gym_invoices"("invoice_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_gym_invoice_line_items"
    ADD CONSTRAINT "fk_line_item_invoice_gym" FOREIGN KEY ("invoice_id", "gym_id") REFERENCES "public"."user_gym_invoices"("invoice_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_invoice_line_items"
    ADD CONSTRAINT "fk_line_item_membership_gym" FOREIGN KEY ("item_id", "gym_id") REFERENCES "public"."member_memberships_unfiltered"("item_id", "gym_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "fk_membership_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "fk_membership_plan_gym" FOREIGN KEY ("plan_id", "gym_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id", "gym_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "fk_membership_price" FOREIGN KEY ("price_id") REFERENCES "public"."membership_plan_prices_unfiltered"("price_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "fk_membership_price_plan" FOREIGN KEY ("price_id", "plan_id") REFERENCES "public"."membership_plan_prices_unfiltered"("price_id", "plan_id");



ALTER TABLE ONLY "public"."member_memberships_unfiltered"
    ADD CONSTRAINT "fk_membership_profile_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."membership_plans_unfiltered"
    ADD CONSTRAINT "fk_plan_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."membership_plan_prices_unfiltered"
    ADD CONSTRAINT "fk_plan_price_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."membership_plan_prices_unfiltered"
    ADD CONSTRAINT "fk_plan_price_plan" FOREIGN KEY ("plan_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id");



ALTER TABLE ONLY "public"."membership_plan_prices_unfiltered"
    ADD CONSTRAINT "fk_plan_price_plan_gym" FOREIGN KEY ("plan_id", "gym_id") REFERENCES "public"."membership_plans_unfiltered"("plan_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "fk_profile_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "fk_profile_linked_account_same_gym" FOREIGN KEY ("account_linked_to_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "fk_profile_linked_discount" FOREIGN KEY ("linked_discount_id") REFERENCES "public"."gym_discounts_unfiltered"("discount_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "fk_profile_linked_discount_gym" FOREIGN KEY ("linked_discount_id", "gym_id") REFERENCES "public"."gym_discounts_unfiltered"("discount_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_profiles_unfiltered"
    ADD CONSTRAINT "fk_profile_user" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_gym_reward_redemptions"
    ADD CONSTRAINT "fk_redemption_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."user_gym_reward_redemptions"
    ADD CONSTRAINT "fk_redemption_reward" FOREIGN KEY ("reward_id") REFERENCES "public"."gym_rewards"("reward_id");



ALTER TABLE ONLY "public"."user_gym_reward_redemptions"
    ADD CONSTRAINT "fk_redemption_reward_gym" FOREIGN KEY ("reward_id", "gym_id") REFERENCES "public"."gym_rewards"("reward_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_reward_redemptions"
    ADD CONSTRAINT "fk_redemption_user_gym" FOREIGN KEY ("crm_user_id", "gym_id") REFERENCES "public"."user_gym_profiles_unfiltered"("crm_user_id", "gym_id");



ALTER TABLE ONLY "public"."user_gym_charges"
    ADD CONSTRAINT "fk_refund_parent" FOREIGN KEY ("refunds_charge_id") REFERENCES "public"."user_gym_charges"("charge_id");



ALTER TABLE ONLY "public"."gym_rewards"
    ADD CONSTRAINT "fk_reward_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_fri_instructor" FOREIGN KEY ("fri_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_mon_instructor" FOREIGN KEY ("mon_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_sat_instructor" FOREIGN KEY ("sat_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_sun_instructor" FOREIGN KEY ("sun_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_thu_instructor" FOREIGN KEY ("thu_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_tue_instructor" FOREIGN KEY ("tue_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_sched_wed_instructor" FOREIGN KEY ("wed_instructor_id", "gym_id") REFERENCES "public"."gym_employees"("employee_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_schedule_class" FOREIGN KEY ("class_id", "gym_id") REFERENCES "public"."gym_classes"("class_id", "gym_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_schedule_class_id" FOREIGN KEY ("class_id") REFERENCES "public"."gym_classes"("class_id");



ALTER TABLE ONLY "public"."gym_class_schedules"
    ADD CONSTRAINT "fk_schedule_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



ALTER TABLE ONLY "public"."stripe_webhook_events"
    ADD CONSTRAINT "fk_webhook_gym" FOREIGN KEY ("gym_id") REFERENCES "public"."gyms"("gym_id");



CREATE POLICY "Employees can view gym staff" ON "public"."gym_employees" FOR SELECT USING ("public"."is_gym_employee"("gym_id"));



CREATE POLICY "Gym employees can view classes" ON "public"."gym_classes" FOR SELECT USING ("public"."is_gym_employee"("gym_id"));



CREATE POLICY "Gym employees can view exceptions" ON "public"."gym_class_exceptions" FOR SELECT USING ("public"."is_gym_employee"("gym_id"));



CREATE POLICY "Gym employees can view schedules" ON "public"."gym_class_schedules" FOR SELECT USING ("public"."is_gym_employee"("gym_id"));



CREATE POLICY "Gym staff can insert activities" ON "public"."user_activities" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can insert class logs" ON "public"."gym_classes_log" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can insert classes" ON "public"."gym_classes" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can insert exceptions" ON "public"."gym_class_exceptions" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can insert rewards" ON "public"."gym_rewards" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can insert schedules" ON "public"."gym_class_schedules" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can update classes" ON "public"."gym_classes" FOR UPDATE USING ("public"."is_gym_admin_or_owner"("gym_id")) WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can update exceptions" ON "public"."gym_class_exceptions" FOR UPDATE USING ("public"."is_gym_admin_or_owner"("gym_id")) WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can update rewards" ON "public"."gym_rewards" FOR UPDATE USING ("public"."is_gym_admin_or_owner"("gym_id")) WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can update schedules" ON "public"."gym_class_schedules" FOR UPDATE USING ("public"."is_gym_admin_or_owner"("gym_id")) WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view discounts" ON "public"."gym_discounts_unfiltered" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view memberships" ON "public"."member_memberships_unfiltered" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view own gym" ON "public"."gyms" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view own gym history" ON "public"."gym_history" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view plan prices" ON "public"."membership_plan_prices_unfiltered" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view plans" ON "public"."membership_plans_unfiltered" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Gym staff can view rewards" ON "public"."gym_rewards" FOR SELECT USING ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Members can view active rewards" ON "public"."gym_rewards" FOR SELECT USING ((("is_active" = true) AND (EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "gym_rewards"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Members can view classes" ON "public"."gym_classes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "gym_classes"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))));



CREATE POLICY "Members can view exceptions" ON "public"."gym_class_exceptions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "gym_class_exceptions"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))));



CREATE POLICY "Members can view gym plans" ON "public"."membership_plans_unfiltered" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "membership_plans_unfiltered"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))));



CREATE POLICY "Members can view own memberships" ON "public"."member_memberships_unfiltered" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."crm_user_id" = "member_memberships_unfiltered"."crm_user_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))));



CREATE POLICY "Members can view plan prices" ON "public"."membership_plan_prices_unfiltered" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "membership_plan_prices_unfiltered"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))));



CREATE POLICY "Members can view schedules" ON "public"."gym_class_schedules" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."gym_classes"
  WHERE (("gym_classes"."class_id" = "gym_class_schedules"."class_id") AND ("gym_classes"."is_active" = true)))) AND (EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."gym_id" = "gym_class_schedules"."gym_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Owners and admins can insert employees" ON "public"."gym_employees" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_gym_admin_or_owner"("gym_id") OR ((("employee_type")::"text" = 'owner'::"text") AND ("user_id" = "auth"."uid"()) AND (NOT "public"."gym_has_owner"("gym_id")))));



CREATE POLICY "Owners and admins can update employees" ON "public"."gym_employees" FOR UPDATE USING ("public"."is_gym_admin_or_owner"("gym_id")) WITH CHECK ("public"."is_gym_admin_or_owner"("gym_id"));



CREATE POLICY "Users and gym staff can view activities" ON "public"."user_activities" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."crm_user_id" = "user_activities"."crm_user_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view applied discounts" ON "public"."user_gym_invoice_applied_discounts" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM ("public"."user_gym_invoices" "inv"
     JOIN "public"."user_gym_profiles_unfiltered" "p" ON (("p"."crm_user_id" = "inv"."crm_user_id")))
  WHERE (("inv"."invoice_id" = "user_gym_invoice_applied_discounts"."invoice_id") AND ("p"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view charges" ON "public"."user_gym_charges" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles_unfiltered"
  WHERE (("user_gym_profiles_unfiltered"."crm_user_id" = "user_gym_charges"."crm_user_id") AND ("user_gym_profiles_unfiltered"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view class logs" ON "public"."gym_classes_log" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles"
  WHERE (("user_gym_profiles"."crm_user_id" = "gym_classes_log"."crm_user_id") AND ("user_gym_profiles"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view invoice line items" ON "public"."user_gym_invoice_line_items" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM ("public"."user_gym_invoices" "inv"
     JOIN "public"."user_gym_profiles_unfiltered" "p" ON (("p"."crm_user_id" = "inv"."crm_user_id")))
  WHERE (("inv"."invoice_id" = "user_gym_invoice_line_items"."invoice_id") AND ("p"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view invoices" ON "public"."user_gym_invoices" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles_unfiltered"
  WHERE (("user_gym_profiles_unfiltered"."crm_user_id" = "user_gym_invoices"."crm_user_id") AND ("user_gym_profiles_unfiltered"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view profiles" ON "public"."user_gym_profiles_unfiltered" FOR SELECT USING ((("auth"."uid"() = "user_id") OR "public"."is_gym_admin_or_owner"("gym_id")));



CREATE POLICY "Users and gym staff can view reward redemptions" ON "public"."user_gym_reward_redemptions" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."user_gym_profiles_unfiltered"
  WHERE (("user_gym_profiles_unfiltered"."crm_user_id" = "user_gym_reward_redemptions"."crm_user_id") AND ("user_gym_profiles_unfiltered"."user_id" = "auth"."uid"())))) OR "public"."is_gym_admin_or_owner"("gym_id")));



ALTER TABLE "public"."gym_class_exceptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_class_schedules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_classes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_classes_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_discounts_unfiltered" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_employees" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gym_rewards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gyms" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hide_incomplete_stripe_records" ON "public"."gym_discounts_unfiltered" AS RESTRICTIVE FOR SELECT TO "authenticated" USING (("stripe_coupon_id" IS NOT NULL));



CREATE POLICY "hide_incomplete_stripe_records" ON "public"."member_memberships_unfiltered" AS RESTRICTIVE FOR SELECT TO "authenticated" USING (("stripe_item_id" IS NOT NULL));



CREATE POLICY "hide_incomplete_stripe_records" ON "public"."membership_plan_prices_unfiltered" AS RESTRICTIVE FOR SELECT TO "authenticated" USING (("stripe_price_id" IS NOT NULL));



CREATE POLICY "hide_incomplete_stripe_records" ON "public"."membership_plans_unfiltered" AS RESTRICTIVE FOR SELECT TO "authenticated" USING (("stripe_product_id" IS NOT NULL));



CREATE POLICY "hide_incomplete_stripe_records" ON "public"."user_gym_profiles_unfiltered" AS RESTRICTIVE FOR SELECT TO "authenticated" USING (("stripe_customer_id" IS NOT NULL));



ALTER TABLE "public"."member_memberships_unfiltered" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."membership_plan_prices_unfiltered" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."membership_plans_unfiltered" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stripe_webhook_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_activities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_charges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_invoice_applied_discounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_invoice_line_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_profiles_unfiltered" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_gym_reward_redemptions" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "service_role";































































































































































GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "postgres";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "anon";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_class_plan_ids_gym_match"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_class_plan_ids_gym_match"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_class_plan_ids_gym_match"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_discount_ids_gym_match"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_discount_ids_gym_match"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_discount_ids_gym_match"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_linked_discount_type"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_linked_discount_type"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_linked_discount_type"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_no_schedule_gaps"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_no_schedule_gaps"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_no_schedule_gaps"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_recurring_chronological_start_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_recurring_chronological_start_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_recurring_chronological_start_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_recurring_no_active_memberships"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_recurring_no_active_memberships"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_recurring_no_active_memberships"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_recurring_no_end_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_recurring_no_end_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_recurring_no_end_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_recurring_no_overlapping_daterange"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_recurring_no_overlapping_daterange"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_recurring_no_overlapping_daterange"() TO "service_role";



GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "postgres";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "anon";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_linked_account_hierarchy"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_linked_account_hierarchy"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_linked_account_hierarchy"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_linked_discount_sequence"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_linked_discount_sequence"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_linked_discount_sequence"() TO "service_role";



GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "postgres";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "anon";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "service_role";



GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gym_has_owner"("p_gym_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."gym_has_owner"("p_gym_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gym_has_owner"("p_gym_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "postgres";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "anon";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "authenticated";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_gym_admin_or_owner"("p_gym_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_gym_admin_or_owner"("p_gym_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_gym_admin_or_owner"("p_gym_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_gym_employee"("p_gym_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_gym_employee"("p_gym_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_gym_employee"("p_gym_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_cancel_date_overwrite"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_cancel_date_overwrite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_cancel_date_overwrite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_plan_id_overwrite"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_plan_id_overwrite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_plan_id_overwrite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_stripe_customer_id_overwrite"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_stripe_customer_id_overwrite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_stripe_customer_id_overwrite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_stripe_item_id_overwrite"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_stripe_item_id_overwrite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_stripe_item_id_overwrite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_user_id_overwrite"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_user_id_overwrite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_user_id_overwrite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "service_role";


















GRANT ALL ON TABLE "public"."gym_class_exceptions" TO "anon";
GRANT ALL ON TABLE "public"."gym_class_exceptions" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_class_exceptions" TO "service_role";



GRANT ALL ON TABLE "public"."gym_class_schedules" TO "anon";
GRANT ALL ON TABLE "public"."gym_class_schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_class_schedules" TO "service_role";



GRANT ALL ON TABLE "public"."gym_classes" TO "anon";
GRANT ALL ON TABLE "public"."gym_classes" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_classes" TO "service_role";



GRANT ALL ON TABLE "public"."gym_classes_log" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."gym_classes_log" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_classes_log" TO "service_role";



GRANT ALL ON TABLE "public"."gym_discounts_unfiltered" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."gym_discounts_unfiltered" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_discounts_unfiltered" TO "service_role";



GRANT ALL ON TABLE "public"."gym_discounts" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."gym_discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_discounts" TO "service_role";



GRANT ALL ON TABLE "public"."gym_employees" TO "anon";
GRANT ALL ON TABLE "public"."gym_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_employees" TO "service_role";



GRANT ALL ON TABLE "public"."gym_history" TO "anon";
GRANT ALL ON TABLE "public"."gym_history" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_history" TO "service_role";



GRANT ALL ON TABLE "public"."gym_rewards" TO "anon";
GRANT ALL ON TABLE "public"."gym_rewards" TO "authenticated";
GRANT ALL ON TABLE "public"."gym_rewards" TO "service_role";



GRANT ALL ON TABLE "public"."gyms" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."gyms" TO "authenticated";
GRANT ALL ON TABLE "public"."gyms" TO "service_role";



GRANT ALL ON TABLE "public"."member_memberships_unfiltered" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."member_memberships_unfiltered" TO "authenticated";
GRANT ALL ON TABLE "public"."member_memberships_unfiltered" TO "service_role";



GRANT ALL ON TABLE "public"."member_memberships" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."member_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."member_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_profiles_unfiltered" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_profiles_unfiltered" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_profiles_unfiltered" TO "service_role";



GRANT ALL ON TABLE "public"."member_memberships_status" TO "anon";
GRANT ALL ON TABLE "public"."member_memberships_status" TO "authenticated";
GRANT ALL ON TABLE "public"."member_memberships_status" TO "service_role";



GRANT ALL ON TABLE "public"."membership_plan_prices_unfiltered" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."membership_plan_prices_unfiltered" TO "authenticated";
GRANT ALL ON TABLE "public"."membership_plan_prices_unfiltered" TO "service_role";



GRANT ALL ON TABLE "public"."membership_plan_prices" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."membership_plan_prices" TO "authenticated";
GRANT ALL ON TABLE "public"."membership_plan_prices" TO "service_role";



GRANT ALL ON TABLE "public"."membership_plans_unfiltered" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."membership_plans_unfiltered" TO "authenticated";
GRANT ALL ON TABLE "public"."membership_plans_unfiltered" TO "service_role";



GRANT ALL ON TABLE "public"."membership_plans" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."membership_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."membership_plans" TO "service_role";



GRANT ALL ON TABLE "public"."stripe_webhook_events" TO "anon";
GRANT ALL ON TABLE "public"."stripe_webhook_events" TO "service_role";



GRANT ALL ON TABLE "public"."user_activities" TO "anon";
GRANT ALL ON TABLE "public"."user_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."user_activities" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_charges" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_charges" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_charges" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_invoice_applied_discounts" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_invoice_applied_discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_invoice_applied_discounts" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_invoice_line_items" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_invoice_line_items" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_invoice_line_items" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_invoices" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_invoices" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_profiles" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."user_gym_reward_redemptions" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_gym_reward_redemptions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_gym_reward_redemptions" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































--
-- Dumped schema changes for auth and storage
--

