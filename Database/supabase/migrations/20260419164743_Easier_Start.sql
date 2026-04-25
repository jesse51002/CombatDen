SET check_function_bodies = false;
ALTER TABLE public.gym_class_schedules DROP CONSTRAINT gym_class_schedules_recurring_unit_check;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_discount_type_check;
ALTER TABLE public.gym_discounts_unfiltered DROP CONSTRAINT gym_discounts_unfiltered_duration_check;
ALTER TABLE public.gym_employees DROP CONSTRAINT gym_employees_employee_type_check;
ALTER TABLE public.gyms_unfiltered DROP CONSTRAINT gyms_unfiltered_stripe_onboarding_status_check;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_duration_unit_check;
ALTER TABLE public.membership_plans_unfiltered DROP CONSTRAINT membership_plans_unfiltered_plan_type_check;
CREATE OR REPLACE FUNCTION public.check_recurring_no_active_memberships()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id
          AND (mm.cancel_date IS NULL OR mm.cancel_date > v_today)
          AND (mm.end_date IS NULL OR mm.end_date > v_today);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while an active membership on the same plan exists'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
ALTER TABLE public.gym_class_schedules ADD CONSTRAINT gym_class_schedules_recurring_unit_check CHECK (recurring_unit::text = ANY (ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying]::text[]));
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_discount_type_check CHECK (discount_type::text = ANY (ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying]::text[]));
ALTER TABLE public.gym_discounts_unfiltered ADD CONSTRAINT gym_discounts_unfiltered_duration_check CHECK (duration::text = ANY (ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying]::text[]));
ALTER TABLE public.gym_employees ADD CONSTRAINT gym_employees_employee_type_check CHECK (employee_type::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'trainer'::character varying]::text[]));
ALTER TABLE public.gyms_unfiltered ADD CONSTRAINT gyms_unfiltered_stripe_onboarding_status_check CHECK (stripe_onboarding_status::text = ANY (ARRAY['not_started'::character varying, 'pending'::character varying, 'complete'::character varying, 'disabled'::character varying]::text[]));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_duration_unit_check CHECK (duration_unit::text = ANY (ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying]::text[]));
ALTER TABLE public.membership_plans_unfiltered ADD CONSTRAINT membership_plans_unfiltered_plan_type_check CHECK (plan_type::text = ANY (ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying]::text[]));
