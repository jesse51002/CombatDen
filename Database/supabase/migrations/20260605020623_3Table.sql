create type "public"."discount_duration_unit" as enum ('day', 'week', 'month');

create type "public"."discount_mode" as enum ('once', 'ongoing');

create type "public"."waiver_signature_type" as enum ('typed');

drop trigger if exists "trg_enforce_linked_discount_sequence_delete" on "public"."gym_discounts_unfiltered";

drop trigger if exists "trg_enforce_linked_discount_sequence_insert_update" on "public"."gym_discounts_unfiltered";

drop trigger if exists "trg_check_discount_ids_gym_match" on "public"."member_memberships_unfiltered";

drop trigger if exists "trg_check_linked_discount_type" on "public"."members";

drop policy "hide_incomplete_stripe_records" on "public"."gym_discounts_unfiltered";

revoke update on table "public"."class_history" from "authenticated";

revoke update on table "public"."member_activities" from "authenticated";

revoke update on table "public"."member_attendance" from "authenticated";

revoke insert on table "public"."member_charges" from "authenticated";

revoke update on table "public"."member_charges" from "authenticated";

revoke insert on table "public"."member_invoice_applied_discounts" from "authenticated";

revoke update on table "public"."member_invoice_applied_discounts" from "authenticated";

revoke insert on table "public"."member_invoice_line_items" from "authenticated";

revoke update on table "public"."member_invoice_line_items" from "authenticated";

revoke insert on table "public"."member_invoices" from "authenticated";

revoke update on table "public"."member_invoices" from "authenticated";

revoke update on table "public"."member_memberships_unfiltered" from "authenticated";

revoke update on table "public"."member_reward_redemptions" from "authenticated";

revoke insert on table "public"."members" from "authenticated";

revoke insert on table "public"."membership_plan_prices_unfiltered" from "authenticated";

revoke update on table "public"."membership_plan_prices_unfiltered" from "authenticated";

revoke update on table "public"."membership_plans_unfiltered" from "authenticated";

revoke delete on table "public"."stripe_webhook_events" from "authenticated";

revoke insert on table "public"."stripe_webhook_events" from "authenticated";

revoke references on table "public"."stripe_webhook_events" from "authenticated";

revoke select on table "public"."stripe_webhook_events" from "authenticated";

revoke trigger on table "public"."stripe_webhook_events" from "authenticated";

revoke truncate on table "public"."stripe_webhook_events" from "authenticated";

revoke update on table "public"."stripe_webhook_events" from "authenticated";

revoke update on table "public"."video_cost_log" from "authenticated";

alter table "public"."gym_discounts_unfiltered" drop constraint "chk_duration_in_months";

alter table "public"."gym_discounts_unfiltered" drop constraint "chk_linked_discount_fields";

alter table "public"."gym_discounts_unfiltered" drop constraint "fk_discount_plan";

alter table "public"."gym_discounts_unfiltered" drop constraint "fk_discount_plan_gym";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_dollar_off_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_duration_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_duration_in_months_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_linked_discount_num_check";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_percentage_off_check";

alter table "public"."members" drop constraint "fk_member_linked_discount";

alter table "public"."members" drop constraint "fk_member_linked_discount_gym";

alter table "public"."gym_discounts_unfiltered" drop constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" drop constraint "membership_plans_unfiltered_plan_type_check";

drop function if exists "public"."check_discount_ids_gym_match"();

drop function if exists "public"."check_linked_discount_type"();

drop function if exists "public"."enforce_linked_discount_sequence"();

drop view if exists "public"."gym_discounts";

drop view if exists "public"."member_billing_profile";

drop view if exists "public"."member_memberships_status";

drop view if exists "public"."membership_plans";

drop view if exists "public"."member_memberships";

drop index if exists "public"."gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key";


  create table "public"."gym_discount_values_unfiltered" (
    "value_id" uuid not null default extensions.uuid_generate_v4(),
    "discount_id" uuid not null,
    "gym_id" uuid not null,
    "percentage_off" double precision,
    "dollar_off" integer,
    "discount_mode" public.discount_mode not null,
    "duration_amount" integer,
    "duration_unit" public.discount_duration_unit,
    "end_date" date,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_discount_values_unfiltered" enable row level security;


  create table "public"."gym_waiver_versions" (
    "version_id" uuid not null default extensions.uuid_generate_v4(),
    "waiver_id" uuid not null,
    "gym_id" uuid not null,
    "version_number" integer not null,
    "body" text not null,
    "content_hash" character varying not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_waiver_versions" enable row level security;


  create table "public"."gym_waivers" (
    "waiver_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "name" character varying not null,
    "current_version_id" uuid,
    "is_deleted" boolean not null default false,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_waivers" enable row level security;


  create table "public"."member_membership_applied_discounts_unfiltered" (
    "applied_discount_id" uuid not null default extensions.uuid_generate_v4(),
    "item_id" uuid not null,
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "value_id" uuid not null,
    "end_date" date,
    "stripe_coupon_id" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_membership_applied_discounts_unfiltered" enable row level security;


  create table "public"."member_waiver_signatures" (
    "signature_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "member_id" uuid not null,
    "waiver_id" uuid not null,
    "waiver_version_id" uuid not null,
    "signed_at" timestamp with time zone not null default now(),
    "signer_name" character varying not null,
    "signature_type" public.waiver_signature_type not null default 'typed'::public.waiver_signature_type,
    "consent_acknowledged" boolean not null,
    "ip_address" inet,
    "user_agent" character varying,
    "content_hash" character varying not null
      );


alter table "public"."member_waiver_signatures" enable row level security;

alter table "public"."gym_classes" add column "allowed_plan_ids" jsonb;

alter table "public"."gym_discounts_unfiltered" drop column "dollar_off";

alter table "public"."gym_discounts_unfiltered" drop column "duration";

alter table "public"."gym_discounts_unfiltered" drop column "duration_in_months";

alter table "public"."gym_discounts_unfiltered" drop column "linked_discount_num";

alter table "public"."gym_discounts_unfiltered" drop column "membership_plan_id";

alter table "public"."gym_discounts_unfiltered" drop column "percentage_off";

alter table "public"."gym_discounts_unfiltered" drop column "stripe_coupon_id";

alter table "public"."member_attendance" add column "item_id" uuid not null;

alter table "public"."member_attendance" add column "plan_id" uuid not null;

alter table "public"."member_memberships_unfiltered" drop column "discount_ids";

alter table "public"."members" drop column "linked_discount_id";

alter table "public"."membership_plans_unfiltered" add column "linked_discount_enabled" boolean not null default false;

alter table "public"."membership_plans_unfiltered" add column "linked_discount_prices" jsonb not null default '[]'::jsonb;

alter table "public"."membership_plans_unfiltered" add column "waiver_ids" jsonb not null default '[]'::jsonb;

CREATE UNIQUE INDEX gym_discount_values_unfiltered_pkey ON public.gym_discount_values_unfiltered USING btree (value_id);

CREATE UNIQUE INDEX gym_discount_values_unfiltered_value_id_gym_id_key ON public.gym_discount_values_unfiltered USING btree (value_id, gym_id);

CREATE UNIQUE INDEX gym_waiver_versions_pkey ON public.gym_waiver_versions USING btree (version_id);

CREATE UNIQUE INDEX gym_waiver_versions_version_id_gym_id_key ON public.gym_waiver_versions USING btree (version_id, gym_id);

CREATE UNIQUE INDEX gym_waiver_versions_waiver_id_version_number_key ON public.gym_waiver_versions USING btree (waiver_id, version_number);

CREATE UNIQUE INDEX gym_waivers_pkey ON public.gym_waivers USING btree (waiver_id);

CREATE UNIQUE INDEX gym_waivers_waiver_id_gym_id_key ON public.gym_waivers USING btree (waiver_id, gym_id);

CREATE INDEX idx_gym_discount_values_discount ON public.gym_discount_values_unfiltered USING btree (discount_id);

CREATE INDEX idx_gym_waiver_versions_waiver ON public.gym_waiver_versions USING btree (waiver_id);

CREATE INDEX idx_gym_waivers_gym ON public.gym_waivers USING btree (gym_id) WHERE (is_deleted = false);

CREATE UNIQUE INDEX idx_max_one_active_discount_value_per_discount ON public.gym_discount_values_unfiltered USING btree (discount_id) WHERE (is_active = true);

CREATE INDEX idx_member_membership_applied_discounts_item ON public.member_membership_applied_discounts_unfiltered USING btree (item_id);

CREATE INDEX idx_member_membership_applied_discounts_member ON public.member_membership_applied_discounts_unfiltered USING btree (member_id, gym_id);

CREATE INDEX idx_member_membership_applied_discounts_value ON public.member_membership_applied_discounts_unfiltered USING btree (value_id);

CREATE INDEX idx_member_waiver_signatures_member ON public.member_waiver_signatures USING btree (member_id, gym_id);

CREATE INDEX idx_member_waiver_signatures_version ON public.member_waiver_signatures USING btree (waiver_version_id);

CREATE INDEX idx_member_waiver_signatures_waiver ON public.member_waiver_signatures USING btree (waiver_id);

CREATE UNIQUE INDEX member_membership_applied_discounts_unfiltered_pkey ON public.member_membership_applied_discounts_unfiltered USING btree (applied_discount_id);

CREATE UNIQUE INDEX member_waiver_signatures_pkey ON public.member_waiver_signatures USING btree (signature_id);

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_pkey" PRIMARY KEY using index "gym_discount_values_unfiltered_pkey";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_pkey" PRIMARY KEY using index "gym_waiver_versions_pkey";

alter table "public"."gym_waivers" add constraint "gym_waivers_pkey" PRIMARY KEY using index "gym_waivers_pkey";

alter table "public"."member_membership_applied_discounts_unfiltered" add constraint "member_membership_applied_discounts_unfiltered_pkey" PRIMARY KEY using index "member_membership_applied_discounts_unfiltered_pkey";

alter table "public"."member_waiver_signatures" add constraint "member_waiver_signatures_pkey" PRIMARY KEY using index "member_waiver_signatures_pkey";

alter table "public"."gym_discount_values_unfiltered" add constraint "chk_discount_value_duration_pair" CHECK (((duration_amount IS NULL) = (duration_unit IS NULL))) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "chk_discount_value_duration_pair";

alter table "public"."gym_discount_values_unfiltered" add constraint "chk_discount_value_lifetime_exclusive" CHECK ((NOT ((duration_amount IS NOT NULL) AND (end_date IS NOT NULL)))) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "chk_discount_value_lifetime_exclusive";

alter table "public"."gym_discount_values_unfiltered" add constraint "fk_discount_value_discount_gym" FOREIGN KEY (discount_id, gym_id) REFERENCES public.gym_discounts_unfiltered(discount_id, gym_id) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "fk_discount_value_discount_gym";

alter table "public"."gym_discount_values_unfiltered" add constraint "fk_discount_value_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "fk_discount_value_gym";

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_check" CHECK ((num_nonnulls(percentage_off, dollar_off) = 1)) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "gym_discount_values_unfiltered_check";

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_dollar_off_check" CHECK ((dollar_off > 0)) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "gym_discount_values_unfiltered_dollar_off_check";

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_duration_amount_check" CHECK ((duration_amount > 0)) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "gym_discount_values_unfiltered_duration_amount_check";

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_percentage_off_check" CHECK (((percentage_off > (0)::double precision) AND (percentage_off <= (100)::double precision))) not valid;

alter table "public"."gym_discount_values_unfiltered" validate constraint "gym_discount_values_unfiltered_percentage_off_check";

alter table "public"."gym_discount_values_unfiltered" add constraint "gym_discount_values_unfiltered_value_id_gym_id_key" UNIQUE using index "gym_discount_values_unfiltered_value_id_gym_id_key";

alter table "public"."gym_waiver_versions" add constraint "fk_waiver_version_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_waiver_versions" validate constraint "fk_waiver_version_gym";

alter table "public"."gym_waiver_versions" add constraint "fk_waiver_version_waiver" FOREIGN KEY (waiver_id) REFERENCES public.gym_waivers(waiver_id) not valid;

alter table "public"."gym_waiver_versions" validate constraint "fk_waiver_version_waiver";

alter table "public"."gym_waiver_versions" add constraint "fk_waiver_version_waiver_gym" FOREIGN KEY (waiver_id, gym_id) REFERENCES public.gym_waivers(waiver_id, gym_id) not valid;

alter table "public"."gym_waiver_versions" validate constraint "fk_waiver_version_waiver_gym";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_body_check" CHECK ((body <> ''::text)) not valid;

alter table "public"."gym_waiver_versions" validate constraint "gym_waiver_versions_body_check";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_content_hash_check" CHECK (((content_hash)::text <> ''::text)) not valid;

alter table "public"."gym_waiver_versions" validate constraint "gym_waiver_versions_content_hash_check";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_version_id_gym_id_key" UNIQUE using index "gym_waiver_versions_version_id_gym_id_key";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_version_number_check" CHECK ((version_number > 0)) not valid;

alter table "public"."gym_waiver_versions" validate constraint "gym_waiver_versions_version_number_check";

alter table "public"."gym_waiver_versions" add constraint "gym_waiver_versions_waiver_id_version_number_key" UNIQUE using index "gym_waiver_versions_waiver_id_version_number_key";

alter table "public"."gym_waivers" add constraint "fk_waiver_current_version" FOREIGN KEY (current_version_id) REFERENCES public.gym_waiver_versions(version_id) not valid;

alter table "public"."gym_waivers" validate constraint "fk_waiver_current_version";

alter table "public"."gym_waivers" add constraint "fk_waiver_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_waivers" validate constraint "fk_waiver_gym";

alter table "public"."gym_waivers" add constraint "gym_waivers_name_check" CHECK (((name)::text <> ''::text)) not valid;

alter table "public"."gym_waivers" validate constraint "gym_waivers_name_check";

alter table "public"."gym_waivers" add constraint "gym_waivers_waiver_id_gym_id_key" UNIQUE using index "gym_waivers_waiver_id_gym_id_key";

alter table "public"."member_attendance" add constraint "fk_attendance_membership_member" FOREIGN KEY (item_id, member_id) REFERENCES public.member_memberships_unfiltered(item_id, member_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_membership_member";

alter table "public"."member_attendance" add constraint "fk_attendance_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_plan_gym";

alter table "public"."member_membership_applied_discounts_unfiltered" add constraint "fk_applied_discount_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_membership_applied_discounts_unfiltered" validate constraint "fk_applied_discount_member_gym";

alter table "public"."member_membership_applied_discounts_unfiltered" add constraint "fk_applied_discount_membership_gym" FOREIGN KEY (item_id, gym_id) REFERENCES public.member_memberships_unfiltered(item_id, gym_id) not valid;

alter table "public"."member_membership_applied_discounts_unfiltered" validate constraint "fk_applied_discount_membership_gym";

alter table "public"."member_membership_applied_discounts_unfiltered" add constraint "fk_applied_discount_value_gym" FOREIGN KEY (value_id, gym_id) REFERENCES public.gym_discount_values_unfiltered(value_id, gym_id) not valid;

alter table "public"."member_membership_applied_discounts_unfiltered" validate constraint "fk_applied_discount_value_gym";

alter table "public"."member_membership_applied_discounts_unfiltered" add constraint "fk_applied_membership_discount_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_membership_applied_discounts_unfiltered" validate constraint "fk_applied_membership_discount_gym";

alter table "public"."member_waiver_signatures" add constraint "chk_waiver_sig_consent" CHECK ((consent_acknowledged = true)) not valid;

alter table "public"."member_waiver_signatures" validate constraint "chk_waiver_sig_consent";

alter table "public"."member_waiver_signatures" add constraint "fk_waiver_sig_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_waiver_signatures" validate constraint "fk_waiver_sig_gym";

alter table "public"."member_waiver_signatures" add constraint "fk_waiver_sig_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_waiver_signatures" validate constraint "fk_waiver_sig_member_gym";

alter table "public"."member_waiver_signatures" add constraint "fk_waiver_sig_version_gym" FOREIGN KEY (waiver_version_id, gym_id) REFERENCES public.gym_waiver_versions(version_id, gym_id) not valid;

alter table "public"."member_waiver_signatures" validate constraint "fk_waiver_sig_version_gym";

alter table "public"."member_waiver_signatures" add constraint "fk_waiver_sig_waiver_gym" FOREIGN KEY (waiver_id, gym_id) REFERENCES public.gym_waivers(waiver_id, gym_id) not valid;

alter table "public"."member_waiver_signatures" validate constraint "fk_waiver_sig_waiver_gym";

alter table "public"."member_waiver_signatures" add constraint "member_waiver_signatures_content_hash_check" CHECK (((content_hash)::text <> ''::text)) not valid;

alter table "public"."member_waiver_signatures" validate constraint "member_waiver_signatures_content_hash_check";

alter table "public"."member_waiver_signatures" add constraint "member_waiver_signatures_signer_name_check" CHECK (((signer_name)::text <> ''::text)) not valid;

alter table "public"."member_waiver_signatures" validate constraint "member_waiver_signatures_signer_name_check";

alter table "public"."membership_plans_unfiltered" add constraint "chk_plan_linked_prices_array" CHECK ((jsonb_typeof(linked_discount_prices) = 'array'::text)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "chk_plan_linked_prices_array";

alter table "public"."membership_plans_unfiltered" add constraint "chk_plan_waiver_ids_array" CHECK ((jsonb_typeof(waiver_ids) = 'array'::text)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "chk_plan_waiver_ids_array";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

create or replace view "public"."gym_discount_values" as  SELECT value_id,
    discount_id,
    gym_id,
    percentage_off,
    dollar_off,
    discount_mode,
    duration_amount,
    duration_unit,
    end_date,
    is_active,
    created_at
   FROM public.gym_discount_values_unfiltered;


create or replace view "public"."member_membership_applied_discounts" as  SELECT applied_discount_id,
    item_id,
    member_id,
    gym_id,
    value_id,
    end_date,
    stripe_coupon_id,
    created_at
   FROM public.member_membership_applied_discounts_unfiltered
  WHERE (stripe_coupon_id IS NOT NULL);


create or replace view "public"."gym_discounts" as  SELECT discount_id,
    gym_id,
    discount_name,
    discount_type,
    is_deleted,
    created_at
   FROM public.gym_discounts_unfiltered;


create or replace view "public"."member_billing_profile" as  SELECT member_id,
    user_id,
    gym_id,
    created_at,
    last_class,
    first_name,
    last_name,
    email,
    points_balance,
    current_rank_id,
    photo_url,
    phone,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    freeze_start_date,
    freeze_end_date,
    account_linked_to_id,
    stripe_customer_id,
    stripe_sub_id_month,
    stripe_payment_method_id,
    payment_type,
    card_brand,
    card_last_four,
    card_exp_month,
    card_exp_year,
    total_monthly_recurring_price
   FROM public.members
  WHERE (stripe_customer_id IS NOT NULL);


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
    prorate,
    total_price,
    created_at
   FROM public.member_memberships_unfiltered
  WHERE (stripe_item_id IS NOT NULL);


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
    mm.prorate,
    mm.total_price,
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
    linked_discount_prices,
    created_at
   FROM public.membership_plans_unfiltered
  WHERE (stripe_product_id IS NOT NULL);


grant delete on table "public"."gym_discount_values_unfiltered" to "anon";

grant insert on table "public"."gym_discount_values_unfiltered" to "anon";

grant references on table "public"."gym_discount_values_unfiltered" to "anon";

grant select on table "public"."gym_discount_values_unfiltered" to "anon";

grant trigger on table "public"."gym_discount_values_unfiltered" to "anon";

grant truncate on table "public"."gym_discount_values_unfiltered" to "anon";

grant update on table "public"."gym_discount_values_unfiltered" to "anon";

grant references on table "public"."gym_discount_values_unfiltered" to "authenticated";

grant select on table "public"."gym_discount_values_unfiltered" to "authenticated";

grant trigger on table "public"."gym_discount_values_unfiltered" to "authenticated";

grant truncate on table "public"."gym_discount_values_unfiltered" to "authenticated";

grant delete on table "public"."gym_discount_values_unfiltered" to "service_role";

grant insert on table "public"."gym_discount_values_unfiltered" to "service_role";

grant references on table "public"."gym_discount_values_unfiltered" to "service_role";

grant select on table "public"."gym_discount_values_unfiltered" to "service_role";

grant trigger on table "public"."gym_discount_values_unfiltered" to "service_role";

grant truncate on table "public"."gym_discount_values_unfiltered" to "service_role";

grant update on table "public"."gym_discount_values_unfiltered" to "service_role";

grant delete on table "public"."gym_waiver_versions" to "anon";

grant insert on table "public"."gym_waiver_versions" to "anon";

grant references on table "public"."gym_waiver_versions" to "anon";

grant select on table "public"."gym_waiver_versions" to "anon";

grant trigger on table "public"."gym_waiver_versions" to "anon";

grant truncate on table "public"."gym_waiver_versions" to "anon";

grant update on table "public"."gym_waiver_versions" to "anon";

grant insert on table "public"."gym_waiver_versions" to "authenticated";

grant references on table "public"."gym_waiver_versions" to "authenticated";

grant select on table "public"."gym_waiver_versions" to "authenticated";

grant trigger on table "public"."gym_waiver_versions" to "authenticated";

grant truncate on table "public"."gym_waiver_versions" to "authenticated";

grant delete on table "public"."gym_waiver_versions" to "service_role";

grant insert on table "public"."gym_waiver_versions" to "service_role";

grant references on table "public"."gym_waiver_versions" to "service_role";

grant select on table "public"."gym_waiver_versions" to "service_role";

grant trigger on table "public"."gym_waiver_versions" to "service_role";

grant truncate on table "public"."gym_waiver_versions" to "service_role";

grant update on table "public"."gym_waiver_versions" to "service_role";

grant delete on table "public"."gym_waivers" to "anon";

grant insert on table "public"."gym_waivers" to "anon";

grant references on table "public"."gym_waivers" to "anon";

grant select on table "public"."gym_waivers" to "anon";

grant trigger on table "public"."gym_waivers" to "anon";

grant truncate on table "public"."gym_waivers" to "anon";

grant update on table "public"."gym_waivers" to "anon";

grant delete on table "public"."gym_waivers" to "authenticated";

grant insert on table "public"."gym_waivers" to "authenticated";

grant references on table "public"."gym_waivers" to "authenticated";

grant select on table "public"."gym_waivers" to "authenticated";

grant trigger on table "public"."gym_waivers" to "authenticated";

grant truncate on table "public"."gym_waivers" to "authenticated";

grant update on table "public"."gym_waivers" to "authenticated";

grant delete on table "public"."gym_waivers" to "service_role";

grant insert on table "public"."gym_waivers" to "service_role";

grant references on table "public"."gym_waivers" to "service_role";

grant select on table "public"."gym_waivers" to "service_role";

grant trigger on table "public"."gym_waivers" to "service_role";

grant truncate on table "public"."gym_waivers" to "service_role";

grant update on table "public"."gym_waivers" to "service_role";

grant delete on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant insert on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant references on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant select on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant trigger on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant truncate on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant update on table "public"."member_membership_applied_discounts_unfiltered" to "anon";

grant delete on table "public"."member_membership_applied_discounts_unfiltered" to "authenticated";

grant references on table "public"."member_membership_applied_discounts_unfiltered" to "authenticated";

grant select on table "public"."member_membership_applied_discounts_unfiltered" to "authenticated";

grant trigger on table "public"."member_membership_applied_discounts_unfiltered" to "authenticated";

grant truncate on table "public"."member_membership_applied_discounts_unfiltered" to "authenticated";

grant delete on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant insert on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant references on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant select on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant trigger on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant truncate on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant update on table "public"."member_membership_applied_discounts_unfiltered" to "service_role";

grant delete on table "public"."member_waiver_signatures" to "anon";

grant insert on table "public"."member_waiver_signatures" to "anon";

grant references on table "public"."member_waiver_signatures" to "anon";

grant select on table "public"."member_waiver_signatures" to "anon";

grant trigger on table "public"."member_waiver_signatures" to "anon";

grant truncate on table "public"."member_waiver_signatures" to "anon";

grant update on table "public"."member_waiver_signatures" to "anon";

grant insert on table "public"."member_waiver_signatures" to "authenticated";

grant references on table "public"."member_waiver_signatures" to "authenticated";

grant select on table "public"."member_waiver_signatures" to "authenticated";

grant trigger on table "public"."member_waiver_signatures" to "authenticated";

grant truncate on table "public"."member_waiver_signatures" to "authenticated";

grant delete on table "public"."member_waiver_signatures" to "service_role";

grant insert on table "public"."member_waiver_signatures" to "service_role";

grant references on table "public"."member_waiver_signatures" to "service_role";

grant select on table "public"."member_waiver_signatures" to "service_role";

grant trigger on table "public"."member_waiver_signatures" to "service_role";

grant truncate on table "public"."member_waiver_signatures" to "service_role";

grant update on table "public"."member_waiver_signatures" to "service_role";


  create policy "Gym staff can view discount values"
  on "public"."gym_discount_values_unfiltered"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can delete discounts"
  on "public"."gym_discounts_unfiltered"
  as permissive
  for delete
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert discounts"
  on "public"."gym_discounts_unfiltered"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update discounts"
  on "public"."gym_discounts_unfiltered"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert waiver versions"
  on "public"."gym_waiver_versions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view waiver versions"
  on "public"."gym_waiver_versions"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can delete waivers"
  on "public"."gym_waivers"
  as permissive
  for delete
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can insert waivers"
  on "public"."gym_waivers"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update waivers"
  on "public"."gym_waivers"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can view waivers"
  on "public"."gym_waivers"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view applied membership discounts"
  on "public"."member_membership_applied_discounts_unfiltered"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members m
  WHERE ((m.member_id = member_membership_applied_discounts_unfiltered.member_id) AND (m.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "hide_incomplete_stripe_records"
  on "public"."member_membership_applied_discounts_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_coupon_id IS NOT NULL));



  create policy "Members and gym staff can view waiver signatures"
  on "public"."member_waiver_signatures"
  as permissive
  for select
  to public
using ((public.is_gym_admin_or_owner(gym_id) OR (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_waiver_signatures.member_id) AND (members.user_id = auth.uid()))))));



