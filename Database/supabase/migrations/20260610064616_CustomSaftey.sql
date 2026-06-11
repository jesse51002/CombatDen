alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_plan_type_check";

drop view if exists "public"."member_membership_applied_discounts";

drop view if exists "public"."member_memberships_status";

drop view if exists "public"."membership_plans";

drop view if exists "public"."member_memberships";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

create or replace view "public"."member_membership_applied_discounts" as  SELECT applied_discount_id,
    item_id,
    member_id,
    gym_id,
    value_id,
    end_date,
    stripe_coupon_id,
    stripe_sync_status,
    created_at
   FROM public.member_membership_applied_discounts_unfiltered
  WHERE ((stripe_coupon_id IS NOT NULL) AND (stripe_sync_status <> ALL (ARRAY['not_added'::public.stripe_sync_status, 'preview_add'::public.stripe_sync_status, 'preview_remove'::public.stripe_sync_status])));


create or replace view "public"."member_memberships" as  SELECT item_id,
    member_id,
    gym_id,
    plan_id,
    price_id,
    start_date,
    end_date,
    cancel_date,
    last_paid_date,
    next_due_date,
    stripe_item_id,
    stripe_one_time_invoice_id,
    prorate,
    total_price,
    stripe_sync_status,
    created_at
   FROM public.member_memberships_unfiltered
  WHERE ((stripe_item_id IS NOT NULL) AND (stripe_sync_status <> ALL (ARRAY['not_added'::public.stripe_sync_status, 'preview_add'::public.stripe_sync_status, 'preview_remove'::public.stripe_sync_status])));


create or replace view "public"."member_memberships_status" as  SELECT mm.item_id,
    mm.member_id,
    mm.gym_id,
    mm.plan_id,
    mm.price_id,
    mm.start_date,
    mm.end_date,
    mm.cancel_date,
    mm.last_paid_date,
    mm.next_due_date,
    mm.stripe_item_id,
    mm.stripe_one_time_invoice_id,
    mm.prorate,
    mm.total_price,
    mm.stripe_sync_status,
    mm.created_at,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
        CASE
            WHEN ((mm.cancel_date IS NOT NULL) AND (mm.cancel_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'cancelled'::text
            WHEN ((mm.end_date IS NOT NULL) AND (mm.end_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'ended'::text
            WHEN ((freeze_owner.freeze_start_date IS NOT NULL) AND (freeze_owner.freeze_end_date IS NOT NULL) AND (freeze_owner.freeze_start_date <= ((now() AT TIME ZONE g.timezone))::date) AND (((now() AT TIME ZONE g.timezone))::date <= freeze_owner.freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM (((public.member_memberships mm
     JOIN public.gyms g ON ((g.gym_id = mm.gym_id)))
     JOIN public.members mbp ON ((mbp.member_id = mm.member_id)))
     JOIN public.members freeze_owner ON ((freeze_owner.member_id = COALESCE(mbp.account_linked_to_id, mbp.member_id))));


create or replace view "public"."membership_plans" as  SELECT plan_id,
    gym_id,
    plan_name,
    plan_type,
    class_count,
    duration_amount,
    duration_unit,
    is_public,
    is_deleted,
    stripe_product_id,
    waiver_ids,
    linked_discount_enabled,
    linked_discount_ids,
    created_at
   FROM public.membership_plans_unfiltered
  WHERE (stripe_product_id IS NOT NULL);



