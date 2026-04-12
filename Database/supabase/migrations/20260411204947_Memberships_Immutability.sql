drop trigger if exists "trg_enforce_family_discount_sequence_delete" on "public"."gym_discounts";

drop trigger if exists "trg_enforce_family_discount_sequence_insert_update" on "public"."gym_discounts";

alter table "public"."gym_classes_log" drop constraint "fk_class_log_membership";

alter table "public"."gym_discounts" drop constraint "chk_family_discount_fields";

alter table "public"."gym_discounts" drop constraint "gym_discounts_family_discount_num_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_gym_id_membership_plan_id_family_discount_num_key";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_user_id_gym_id_key";

alter table "public"."gym_class_schedules" drop constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_discount_type_check";

alter table "public"."gym_discounts" drop constraint "gym_discounts_duration_check";

alter table "public"."gym_employees" drop constraint "gym_employees_employee_type_check";

alter table "public"."gyms" drop constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans" drop constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" drop constraint "membership_plans_plan_type_check";

drop function if exists "public"."enforce_family_discount_sequence"();

drop view if exists "public"."member_memberships_status";

alter table "public"."member_memberships" drop constraint "member_memberships_pkey";

drop index if exists "public"."gym_discounts_gym_id_membership_plan_id_family_discount_num_key";

drop index if exists "public"."user_gym_profiles_user_id_gym_id_key";

drop index if exists "public"."idx_profiles_stripe_customer";

drop index if exists "public"."member_memberships_pkey";

alter table "public"."gym_classes_log" add column "item_id" uuid not null;

alter table "public"."gym_discounts" drop column "discount_active";

alter table "public"."gym_discounts" drop column "family_discount_num";

alter table "public"."gym_discounts" add column "linked_discount_num" integer;

alter table "public"."member_memberships" drop column "freeze_end_date";

alter table "public"."member_memberships" drop column "freeze_start_date";

alter table "public"."member_memberships" drop column "price_formula";

alter table "public"."member_memberships" drop column "stripe_id";

alter table "public"."member_memberships" add column "item_id" uuid not null default extensions.uuid_generate_v4();

alter table "public"."member_memberships" add column "prorate" boolean not null default true;

alter table "public"."member_memberships" add column "stripe_item_id" character varying not null;

alter table "public"."membership_plan_prices" alter column "stripe_price_id" set not null;

alter table "public"."membership_plans" alter column "duration_amount" drop not null;

alter table "public"."membership_plans" alter column "duration_unit" drop not null;

alter table "public"."user_gym_profiles" drop column "stripe_sub_id_week";

alter table "public"."user_gym_profiles" drop column "stripe_sub_id_year";

alter table "public"."user_gym_profiles" add column "freeze_end_date" date;

alter table "public"."user_gym_profiles" add column "freeze_start_date" date;

alter table "public"."user_gym_profiles" add column "linked_discount_id" uuid;

alter table "public"."user_gym_profiles" alter column "stripe_customer_id" set not null;

CREATE UNIQUE INDEX gym_discounts_gym_id_membership_plan_id_linked_discount_num_key ON public.gym_discounts USING btree (gym_id, membership_plan_id, linked_discount_num);

CREATE UNIQUE INDEX member_memberships_item_id_crm_user_id_key ON public.member_memberships USING btree (item_id, crm_user_id);

CREATE UNIQUE INDEX idx_profiles_stripe_customer ON public.user_gym_profiles USING btree (stripe_customer_id);

CREATE UNIQUE INDEX member_memberships_pkey ON public.member_memberships USING btree (item_id);

alter table "public"."member_memberships" add constraint "member_memberships_pkey" PRIMARY KEY using index "member_memberships_pkey";

alter table "public"."gym_classes_log" add constraint "fk_class_log_membership_item" FOREIGN KEY (item_id, crm_user_id) REFERENCES public.member_memberships(item_id, crm_user_id) not valid;

alter table "public"."gym_classes_log" validate constraint "fk_class_log_membership_item";

alter table "public"."gym_discounts" add constraint "chk_linked_discount_fields" CHECK (((((discount_type)::text = 'linked'::text) AND (membership_plan_id IS NOT NULL) AND (linked_discount_num IS NOT NULL) AND (dollar_off IS NOT NULL)) OR (((discount_type)::text <> 'linked'::text) AND (membership_plan_id IS NULL) AND (linked_discount_num IS NULL)))) not valid;

alter table "public"."gym_discounts" validate constraint "chk_linked_discount_fields";

alter table "public"."gym_discounts" add constraint "gym_discounts_gym_id_membership_plan_id_linked_discount_num_key" UNIQUE using index "gym_discounts_gym_id_membership_plan_id_linked_discount_num_key";

alter table "public"."gym_discounts" add constraint "gym_discounts_linked_discount_num_check" CHECK ((linked_discount_num > 0)) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_linked_discount_num_check";

alter table "public"."member_memberships" add constraint "member_memberships_item_id_crm_user_id_key" UNIQUE using index "member_memberships_item_id_crm_user_id_key";

alter table "public"."membership_plans" add constraint "duration_both_or_neither" CHECK (((duration_amount IS NULL) = (duration_unit IS NULL))) not valid;

alter table "public"."membership_plans" validate constraint "duration_both_or_neither";

alter table "public"."membership_plans" add constraint "duration_required_unless_class_count" CHECK ((((duration_amount IS NOT NULL) AND (duration_unit IS NOT NULL)) OR (((plan_type)::text <> 'recurring'::text) AND (class_count IS NOT NULL)))) not valid;

alter table "public"."membership_plans" validate constraint "duration_required_unless_class_count";

alter table "public"."membership_plans" add constraint "recurring_must_be_monthly" CHECK ((((plan_type)::text <> 'recurring'::text) OR (((duration_unit)::text = 'month'::text) AND (duration_amount = 1)))) not valid;

alter table "public"."membership_plans" validate constraint "recurring_must_be_monthly";

alter table "public"."user_gym_profiles" add constraint "fk_profile_linked_discount" FOREIGN KEY (linked_discount_id) REFERENCES public.gym_discounts(discount_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_linked_discount";

alter table "public"."user_gym_profiles" add constraint "fk_profile_linked_discount_gym" FOREIGN KEY (linked_discount_id, gym_id) REFERENCES public.gym_discounts(discount_id, gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_linked_discount_gym";

alter table "public"."user_gym_profiles" add constraint "freeze_dates_must_be_paired" CHECK ((((freeze_start_date IS NULL) AND (freeze_end_date IS NULL)) OR ((freeze_start_date IS NOT NULL) AND (freeze_end_date IS NOT NULL)))) not valid;

alter table "public"."user_gym_profiles" validate constraint "freeze_dates_must_be_paired";

alter table "public"."user_gym_profiles" add constraint "linked_account_no_stripe" CHECK (((account_linked_to_id IS NULL) OR ((stripe_sub_id_month IS NULL) AND (freeze_start_date IS NULL) AND (freeze_end_date IS NULL) AND (payment_type IS NULL) AND (card_brand IS NULL) AND (card_last_four IS NULL) AND (card_exp_month IS NULL) AND (card_exp_year IS NULL)))) not valid;

alter table "public"."user_gym_profiles" validate constraint "linked_account_no_stripe";

alter table "public"."gym_class_schedules" add constraint "gym_class_schedules_recurring_unit_check" CHECK (((recurring_unit)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying])::text[]))) not valid;

alter table "public"."gym_class_schedules" validate constraint "gym_class_schedules_recurring_unit_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_discount_type_check";

alter table "public"."gym_discounts" add constraint "gym_discounts_duration_check" CHECK (((duration)::text = ANY ((ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts" validate constraint "gym_discounts_duration_check";

alter table "public"."gym_employees" add constraint "gym_employees_employee_type_check" CHECK (((employee_type)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying])::text[]))) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_employee_type_check";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_check" CHECK (((stripe_onboarding_status)::text = ANY ((ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_check";

alter table "public"."membership_plans" add constraint "membership_plans_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_duration_unit_check";

alter table "public"."membership_plans" add constraint "membership_plans_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans" validate constraint "membership_plans_plan_type_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_linked_discount_type()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.linked_discount_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM gym_discounts
            WHERE discount_id = NEW.linked_discount_id
              AND discount_type = 'linked'
        ) THEN
            RAISE EXCEPTION 'linked_discount_id % must reference a discount with type linked', NEW.linked_discount_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_recurring_chronological_start_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_plan_type VARCHAR;
    v_max_start_date DATE;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships mm
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
$function$
;

CREATE OR REPLACE FUNCTION public.check_recurring_no_active_memberships()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_plan_type VARCHAR;
    v_active_count INTEGER;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT COUNT(*) INTO v_active_count
        FROM member_memberships mm
        WHERE mm.crm_user_id = NEW.crm_user_id
          AND mm.gym_id = NEW.gym_id
          AND mm.item_id <> NEW.item_id
          AND (mm.cancel_date IS NULL OR mm.cancel_date > CURRENT_DATE)
          AND (mm.end_date IS NULL OR mm.end_date > CURRENT_DATE);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while active memberships exist'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_recurring_no_end_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.end_date IS NOT NULL THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships cannot have an end_date'
                USING CONSTRAINT = 'recurring_no_end_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_recurring_no_overlapping_daterange()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships mm
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
$function$
;

CREATE OR REPLACE FUNCTION public.enforce_linked_discount_sequence()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    max_num INTEGER;
    total_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts
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
            FROM gym_discounts
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
        FROM gym_discounts
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
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_cancel_date_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.cancel_date IS NOT NULL AND NEW.cancel_date IS DISTINCT FROM OLD.cancel_date THEN
        RAISE EXCEPTION 'cancel_date cannot be changed once set'
            USING CONSTRAINT = 'cancel_date_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_plan_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
        RAISE EXCEPTION 'plan_id cannot be changed after creation'
            USING CONSTRAINT = 'plan_id_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_stripe_item_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed after creation'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

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
     JOIN public.user_gym_profiles ugp ON ((ugp.crm_user_id = mm.crm_user_id)))
     JOIN public.user_gym_profiles freeze_owner ON ((freeze_owner.crm_user_id = COALESCE(ugp.account_linked_to_id, ugp.crm_user_id))));


CREATE OR REPLACE FUNCTION public.prevent_stripe_customer_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE TRIGGER trg_enforce_linked_discount_sequence_delete BEFORE DELETE ON public.gym_discounts FOR EACH ROW WHEN (((old.discount_type)::text = 'linked'::text)) EXECUTE FUNCTION public.enforce_linked_discount_sequence();

CREATE TRIGGER trg_enforce_linked_discount_sequence_insert_update BEFORE INSERT OR UPDATE OF linked_discount_num ON public.gym_discounts FOR EACH ROW WHEN (((new.discount_type)::text = 'linked'::text)) EXECUTE FUNCTION public.enforce_linked_discount_sequence();

CREATE TRIGGER trg_prevent_cancel_date_overwrite BEFORE UPDATE OF cancel_date ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.prevent_cancel_date_overwrite();

CREATE TRIGGER trg_prevent_plan_id_overwrite BEFORE UPDATE OF plan_id ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.prevent_plan_id_overwrite();

CREATE TRIGGER trg_prevent_stripe_item_id_overwrite BEFORE UPDATE OF stripe_item_id ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_item_id_overwrite();

CREATE TRIGGER trg_recurring_chronological_start_date BEFORE INSERT ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_recurring_chronological_start_date();

CREATE TRIGGER trg_recurring_no_active_memberships BEFORE INSERT ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_active_memberships();

CREATE TRIGGER trg_recurring_no_end_date BEFORE INSERT OR UPDATE OF end_date ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_end_date();

CREATE TRIGGER trg_recurring_no_overlapping_daterange BEFORE INSERT OR UPDATE OF cancel_date ON public.member_memberships FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_overlapping_daterange();

CREATE TRIGGER trg_check_linked_discount_type BEFORE INSERT OR UPDATE OF linked_discount_id ON public.user_gym_profiles FOR EACH ROW EXECUTE FUNCTION public.check_linked_discount_type();


