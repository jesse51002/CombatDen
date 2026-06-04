create type "public"."charge_kind" as enum ('payment', 'refund');

create type "public"."charge_status" as enum ('pending', 'succeeded', 'failed');

create type "public"."employee_type" as enum ('owner', 'admin', 'trainer');

create type "public"."gym_type" as enum ('bjj', 'mma', 'generic');

create type "public"."invoice_status" as enum ('open', 'paid');

create type "public"."line_item_type" as enum ('membership', 'custom');

create type "public"."recurring_unit" as enum ('daily', 'weekly', 'monthly');

create type "public"."video_execution_type" as enum ('search', 'transcript', 'tag', 'scan');

create type "public"."video_genre" as enum ('educational', 'analysis', 'entertainment', 'news', 'interview', 'vlog', 'professional', 'clips', 'memes');

create type "public"."video_gym_feed_status" as enum ('good', 'rejected');


  create table "public"."class_history" (
    "class_history_id" uuid not null default extensions.uuid_generate_v4(),
    "class_id" uuid not null,
    "gym_id" uuid not null,
    "instructor_id" uuid,
    "occurred_at" timestamp with time zone not null,
    "duration_minutes" integer not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."class_history" enable row level security;


  create table "public"."class_instance_exceptions" (
    "exception_id" uuid not null default extensions.uuid_generate_v4(),
    "class_id" uuid not null,
    "gym_id" uuid not null,
    "original_date" date not null,
    "is_cancelled" boolean not null default false,
    "new_class_time" time without time zone,
    "new_duration_minutes" integer,
    "new_max_capacity" integer,
    "new_instructor_id" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."class_instance_exceptions" enable row level security;


  create table "public"."class_range_exceptions" (
    "exception_id" uuid not null default extensions.uuid_generate_v4(),
    "class_id" uuid not null,
    "gym_id" uuid not null,
    "start_date" date not null,
    "end_date" date not null,
    "is_cancelled" boolean not null default false,
    "new_instructor_id" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."class_range_exceptions" enable row level security;


  create table "public"."gym_classes" (
    "class_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "class_name" character varying not null,
    "class_description" character varying,
    "max_capacity" integer,
    "image_url" character varying,
    "points_worth" integer not null default 50,
    "is_active" boolean not null default true,
    "is_deleted" boolean not null default false,
    "class_time" time without time zone not null,
    "duration_minutes" integer not null,
    "recurring_unit" public.recurring_unit not null,
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
    "start_date" date not null,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_classes" enable row level security;


  create table "public"."gym_discounts_unfiltered" (
    "discount_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "discount_name" character varying not null,
    "discount_type" character varying not null,
    "percentage_off" double precision,
    "dollar_off" integer,
    "membership_plan_id" uuid,
    "linked_discount_num" integer,
    "duration" character varying not null,
    "duration_in_months" integer,
    "is_deleted" boolean not null default false,
    "stripe_coupon_id" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_discounts_unfiltered" enable row level security;


  create table "public"."gym_employees" (
    "employee_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid,
    "gym_id" uuid not null,
    "employee_type" public.employee_type not null,
    "first_name" character varying not null,
    "last_name" character varying not null,
    "phone" character varying,
    "email" character varying,
    "employee_pic_url" character varying,
    "employee_public_description" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_employees" enable row level security;


  create table "public"."gym_history" (
    "gym_id" uuid not null,
    "date" date not null,
    "total_active" integer not null,
    "total_inactive" integer not null,
    "went_inactive" integer not null,
    "became_active" integer not null
      );


alter table "public"."gym_history" enable row level security;


  create table "public"."gym_ranks" (
    "rank_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "main_rank_num_order" integer not null,
    "sub_rank_num_order" integer not null,
    "main_name" character varying not null,
    "sub_name" character varying not null,
    "classes_till_rankup" integer not null,
    "image_url" character varying,
    "color" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_ranks" enable row level security;


  create table "public"."gym_rewards" (
    "reward_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "title" character varying not null,
    "amount_off" character varying,
    "image_url" character varying,
    "point_cost" integer not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."gym_rewards" enable row level security;


  create table "public"."gyms" (
    "gym_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_name" character varying not null,
    "gym_description" character varying,
    "timezone" text not null default 'America/Chicago'::text,
    "is_rank_enabled" boolean not null default true,
    "stripe_account_id" text,
    "stripe_onboarding_status" text not null default 'not_started'::text
      );


alter table "public"."gyms" enable row level security;


  create table "public"."member_activities" (
    "activity_id" uuid not null default extensions.uuid_generate_v4(),
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "activity_type" character varying not null,
    "activity_info" jsonb default '{}'::jsonb,
    "time" timestamp with time zone not null default now()
      );


alter table "public"."member_activities" enable row level security;


  create table "public"."member_attendance" (
    "log_id" uuid not null default extensions.uuid_generate_v4(),
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "class_history_id" uuid not null
      );


alter table "public"."member_attendance" enable row level security;


  create table "public"."member_charges" (
    "charge_id" uuid not null default extensions.uuid_generate_v4(),
    "invoice_id" uuid not null,
    "gym_id" uuid not null,
    "member_id" uuid not null,
    "kind" public.charge_kind not null,
    "status" public.charge_status not null,
    "amount" integer not null,
    "currency" character(3) not null default 'usd'::bpchar,
    "payment_method_type" character varying,
    "stripe_charge_id" character varying,
    "stripe_refund_id" character varying,
    "refunds_charge_id" uuid,
    "charge_time" timestamp with time zone not null default now(),
    "stripe_event_payload" jsonb
      );


alter table "public"."member_charges" enable row level security;


  create table "public"."member_invoice_applied_discounts" (
    "applied_discount_id" uuid not null default extensions.uuid_generate_v4(),
    "invoice_id" uuid not null,
    "gym_id" uuid not null,
    "discount_id" uuid not null,
    "amount_off" integer not null,
    "stripe_coupon_id" character varying
      );


alter table "public"."member_invoice_applied_discounts" enable row level security;


  create table "public"."member_invoice_line_items" (
    "line_item_id" character varying not null,
    "invoice_id" uuid not null,
    "gym_id" uuid not null,
    "item_type" public.line_item_type not null,
    "name" character varying not null,
    "amount" integer not null,
    "stripe_product_id" character varying,
    "item_id" uuid
      );


alter table "public"."member_invoice_line_items" enable row level security;


  create table "public"."member_invoices" (
    "invoice_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "member_id" uuid not null,
    "status" public.invoice_status not null default 'open'::public.invoice_status,
    "total_amount" integer not null,
    "currency" character(3) not null default 'usd'::bpchar,
    "stripe_invoice_id" character varying,
    "stripe_payment_intent_id" character varying,
    "invoice_time" timestamp with time zone not null default now(),
    "stripe_event_payload" jsonb
      );


alter table "public"."member_invoices" enable row level security;


  create table "public"."member_memberships_unfiltered" (
    "item_id" uuid not null default extensions.uuid_generate_v4(),
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "plan_id" uuid not null,
    "price_id" uuid not null,
    "start_date" date not null,
    "end_date" date,
    "cancel_date" date,
    "last_paid_date" date,
    "next_due_date" date,
    "discount_ids" jsonb,
    "stripe_item_id" character varying,
    "prorate" boolean not null default true,
    "total_price" integer not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_memberships_unfiltered" enable row level security;


  create table "public"."member_reward_redemptions" (
    "redemption_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "member_id" uuid not null,
    "reward_id" uuid not null,
    "point_cost" integer not null,
    "redeemed_at" timestamp with time zone not null default now()
      );


alter table "public"."member_reward_redemptions" enable row level security;


  create table "public"."members" (
    "member_id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid,
    "gym_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "last_class" timestamp with time zone,
    "first_name" character varying not null,
    "last_name" character varying not null,
    "email" character varying,
    "points_balance" integer not null default 0,
    "current_rank_id" uuid,
    "photo_url" character varying,
    "phone" character varying,
    "address" character varying,
    "emergency_contact_name" character varying,
    "emergency_contact_phone" character varying,
    "emergency_contact_email" character varying,
    "freeze_start_date" date,
    "freeze_end_date" date,
    "account_linked_to_id" uuid,
    "linked_discount_id" uuid,
    "stripe_customer_id" character varying,
    "stripe_sub_id_month" character varying,
    "stripe_payment_method_id" character varying,
    "payment_type" character varying,
    "card_brand" character varying,
    "card_last_four" character varying(4),
    "card_exp_month" integer,
    "card_exp_year" integer,
    "total_monthly_recurring_price" integer not null default 0
      );


alter table "public"."members" enable row level security;


  create table "public"."membership_plan_prices_unfiltered" (
    "price_id" uuid not null default extensions.uuid_generate_v4(),
    "plan_id" uuid not null,
    "gym_id" uuid not null,
    "stripe_price_id" character varying,
    "price" integer not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."membership_plan_prices_unfiltered" enable row level security;


  create table "public"."membership_plans_unfiltered" (
    "plan_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "plan_name" character varying not null,
    "plan_type" character varying not null,
    "class_count" integer,
    "duration_amount" integer,
    "duration_unit" character varying,
    "is_public" boolean not null default true,
    "is_deleted" boolean not null default false,
    "stripe_product_id" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."membership_plans_unfiltered" enable row level security;


  create table "public"."rank_presets" (
    "preset_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_type" public.gym_type not null,
    "main_rank_num_order" integer not null,
    "sub_rank_num_order" integer not null,
    "main_name" character varying not null,
    "sub_name" character varying not null,
    "classes_till_rankup" integer not null,
    "image_url" character varying,
    "color" character varying,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."rank_presets" enable row level security;


  create table "public"."stripe_webhook_events" (
    "event_id" character varying not null,
    "gym_id" uuid not null,
    "event_type" character varying not null,
    "processed_at" timestamp with time zone not null default now()
      );


alter table "public"."stripe_webhook_events" enable row level security;


  create table "public"."video" (
    "video_id" text not null,
    "url" text not null,
    "title" text not null,
    "description" text not null default ''::text,
    "thumbnail_url" text not null,
    "channel_name" text not null,
    "channel_url" text not null,
    "channel_avatar_url" text not null default ''::text,
    "view_count" integer,
    "like_count" integer,
    "duration_seconds" integer,
    "tag" public.video_genre,
    "disciplines" jsonb not null default '[]'::jsonb,
    "source_queries" jsonb not null default '[]'::jsonb,
    "relevance_index" integer not null,
    "transcript_error" text,
    "transcript" text
      );


alter table "public"."video" enable row level security;


  create table "public"."video_cost_log" (
    "entry_id" uuid not null default extensions.uuid_generate_v4(),
    "execution_type" public.video_execution_type not null,
    "gym_id" text,
    "at" timestamp with time zone not null,
    "breakdown" jsonb not null default '{}'::jsonb,
    "note" text
      );


alter table "public"."video_cost_log" enable row level security;


  create table "public"."video_gym" (
    "gym_id" text not null,
    "gym_type" jsonb not null,
    "theme" text not null,
    "short_videos_desc" text,
    "short_avoid_desc" text,
    "videos_desc" text not null,
    "avoid_desc" text not null,
    "has_classes" boolean not null default false,
    "has_rewards" boolean not null default false
      );


alter table "public"."video_gym" enable row level security;


  create table "public"."video_gym_class" (
    "class_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" text not null,
    "name" text not null,
    "image_url" text not null,
    "description" text not null,
    "instructor_name" text not null,
    "instructor_bio" text not null,
    "instructor_image_url" text not null
      );


alter table "public"."video_gym_class" enable row level security;


  create table "public"."video_gym_feed" (
    "gym_id" text not null,
    "video_id" text not null,
    "status" public.video_gym_feed_status not null
      );


alter table "public"."video_gym_feed" enable row level security;


  create table "public"."video_gym_query" (
    "query_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" text not null,
    "query" text not null
      );


alter table "public"."video_gym_query" enable row level security;


  create table "public"."video_gym_reward" (
    "reward_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" text not null,
    "title" text not null,
    "image_url" text not null,
    "price_label" text not null,
    "points_cost" integer not null
      );


alter table "public"."video_gym_reward" enable row level security;

CREATE UNIQUE INDEX class_history_class_history_id_gym_id_key ON public.class_history USING btree (class_history_id, gym_id);

CREATE UNIQUE INDEX class_history_pkey ON public.class_history USING btree (class_history_id);

CREATE UNIQUE INDEX class_instance_exceptions_class_id_original_date_key ON public.class_instance_exceptions USING btree (class_id, original_date);

CREATE UNIQUE INDEX class_instance_exceptions_pkey ON public.class_instance_exceptions USING btree (exception_id);

CREATE UNIQUE INDEX class_range_exceptions_pkey ON public.class_range_exceptions USING btree (exception_id);

CREATE UNIQUE INDEX gym_classes_class_id_gym_id_key ON public.gym_classes USING btree (class_id, gym_id);

CREATE UNIQUE INDEX gym_classes_pkey ON public.gym_classes USING btree (class_id);

CREATE UNIQUE INDEX gym_discounts_unfiltered_discount_id_gym_id_key ON public.gym_discounts_unfiltered USING btree (discount_id, gym_id);

CREATE UNIQUE INDEX gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key ON public.gym_discounts_unfiltered USING btree (gym_id, membership_plan_id, linked_discount_num);

CREATE UNIQUE INDEX gym_discounts_unfiltered_pkey ON public.gym_discounts_unfiltered USING btree (discount_id);

CREATE UNIQUE INDEX gym_employees_employee_id_gym_id_key ON public.gym_employees USING btree (employee_id, gym_id);

CREATE UNIQUE INDEX gym_employees_pkey ON public.gym_employees USING btree (employee_id);

CREATE UNIQUE INDEX gym_employees_user_id_gym_id_key ON public.gym_employees USING btree (user_id, gym_id);

CREATE UNIQUE INDEX gym_history_pkey ON public.gym_history USING btree (gym_id, date);

CREATE UNIQUE INDEX gym_ranks_gym_id_main_rank_num_order_sub_rank_num_order_key ON public.gym_ranks USING btree (gym_id, main_rank_num_order, sub_rank_num_order);

CREATE UNIQUE INDEX gym_ranks_pkey ON public.gym_ranks USING btree (rank_id);

CREATE UNIQUE INDEX gym_ranks_rank_id_gym_id_key ON public.gym_ranks USING btree (rank_id, gym_id);

CREATE UNIQUE INDEX gym_rewards_pkey ON public.gym_rewards USING btree (reward_id);

CREATE UNIQUE INDEX gym_rewards_reward_id_gym_id_key ON public.gym_rewards USING btree (reward_id, gym_id);

CREATE UNIQUE INDEX gyms_pkey ON public.gyms USING btree (gym_id);

CREATE UNIQUE INDEX gyms_stripe_account_id_key ON public.gyms USING btree (stripe_account_id);

CREATE INDEX idx_applied_discounts_invoice ON public.member_invoice_applied_discounts USING btree (invoice_id);

CREATE INDEX idx_charges_gym_time ON public.member_charges USING btree (gym_id, charge_time DESC);

CREATE INDEX idx_charges_invoice ON public.member_charges USING btree (invoice_id);

CREATE INDEX idx_charges_member_gym_time ON public.member_charges USING btree (member_id, gym_id, charge_time DESC);

CREATE INDEX idx_class_history_class_time ON public.class_history USING btree (class_id, occurred_at DESC);

CREATE INDEX idx_invoices_gym_time ON public.member_invoices USING btree (gym_id, invoice_time DESC);

CREATE INDEX idx_invoices_member_gym_time ON public.member_invoices USING btree (member_id, gym_id, invoice_time DESC);

CREATE INDEX idx_line_items_invoice ON public.member_invoice_line_items USING btree (invoice_id);

CREATE INDEX idx_line_items_item ON public.member_invoice_line_items USING btree (item_id) WHERE (item_id IS NOT NULL);

CREATE UNIQUE INDEX idx_max_one_active_price_per_plan ON public.membership_plan_prices_unfiltered USING btree (plan_id) WHERE (is_active = true);

CREATE INDEX idx_member_attendance_class_history ON public.member_attendance USING btree (class_history_id);

CREATE INDEX idx_member_attendance_member_gym ON public.member_attendance USING btree (member_id, gym_id);

CREATE INDEX idx_member_reward_redemptions_member_gym_time ON public.member_reward_redemptions USING btree (member_id, gym_id, redeemed_at DESC);

CREATE UNIQUE INDEX idx_members_stripe_customer ON public.members USING btree (stripe_customer_id);

CREATE INDEX idx_video_cost_log_gym ON public.video_cost_log USING btree (gym_id);

CREATE INDEX idx_video_disciplines ON public.video USING gin (disciplines);

CREATE INDEX idx_video_gym_class_gym ON public.video_gym_class USING btree (gym_id);

CREATE INDEX idx_video_gym_feed_serve ON public.video_gym_feed USING btree (gym_id, status);

CREATE INDEX idx_video_gym_query_gym ON public.video_gym_query USING btree (gym_id);

CREATE INDEX idx_video_gym_reward_gym ON public.video_gym_reward USING btree (gym_id);

CREATE INDEX idx_video_tag ON public.video USING btree (tag);

CREATE INDEX idx_webhook_events_gym ON public.stripe_webhook_events USING btree (gym_id, processed_at DESC);

CREATE UNIQUE INDEX member_activities_pkey ON public.member_activities USING btree (activity_id);

CREATE UNIQUE INDEX member_attendance_member_id_class_history_id_key ON public.member_attendance USING btree (member_id, class_history_id);

CREATE UNIQUE INDEX member_attendance_pkey ON public.member_attendance USING btree (log_id);

CREATE UNIQUE INDEX member_charges_pkey ON public.member_charges USING btree (charge_id);

CREATE UNIQUE INDEX member_charges_stripe_charge_id_key ON public.member_charges USING btree (stripe_charge_id);

CREATE UNIQUE INDEX member_charges_stripe_refund_id_key ON public.member_charges USING btree (stripe_refund_id);

CREATE UNIQUE INDEX member_invoice_applied_discounts_pkey ON public.member_invoice_applied_discounts USING btree (applied_discount_id);

CREATE UNIQUE INDEX member_invoice_line_items_pkey ON public.member_invoice_line_items USING btree (line_item_id);

CREATE UNIQUE INDEX member_invoices_invoice_id_gym_id_key ON public.member_invoices USING btree (invoice_id, gym_id);

CREATE UNIQUE INDEX member_invoices_pkey ON public.member_invoices USING btree (invoice_id);

CREATE UNIQUE INDEX member_invoices_stripe_invoice_id_key ON public.member_invoices USING btree (stripe_invoice_id);

CREATE UNIQUE INDEX member_invoices_stripe_payment_intent_id_key ON public.member_invoices USING btree (stripe_payment_intent_id);

CREATE UNIQUE INDEX member_memberships_unfiltered_item_id_gym_id_key ON public.member_memberships_unfiltered USING btree (item_id, gym_id);

CREATE UNIQUE INDEX member_memberships_unfiltered_item_id_member_id_key ON public.member_memberships_unfiltered USING btree (item_id, member_id);

CREATE UNIQUE INDEX member_memberships_unfiltered_pkey ON public.member_memberships_unfiltered USING btree (item_id);

CREATE UNIQUE INDEX member_reward_redemptions_pkey ON public.member_reward_redemptions USING btree (redemption_id);

CREATE UNIQUE INDEX members_member_id_gym_id_key ON public.members USING btree (member_id, gym_id);

CREATE UNIQUE INDEX members_pkey ON public.members USING btree (member_id);

CREATE UNIQUE INDEX membership_plan_prices_unfiltered_pkey ON public.membership_plan_prices_unfiltered USING btree (price_id);

CREATE UNIQUE INDEX membership_plan_prices_unfiltered_price_id_plan_id_key ON public.membership_plan_prices_unfiltered USING btree (price_id, plan_id);

CREATE UNIQUE INDEX membership_plans_unfiltered_pkey ON public.membership_plans_unfiltered USING btree (plan_id);

CREATE UNIQUE INDEX membership_plans_unfiltered_plan_id_gym_id_key ON public.membership_plans_unfiltered USING btree (plan_id, gym_id);

CREATE UNIQUE INDEX pk_video ON public.video USING btree (video_id);

CREATE UNIQUE INDEX pk_video_cost_log ON public.video_cost_log USING btree (entry_id);

CREATE UNIQUE INDEX pk_video_gym ON public.video_gym USING btree (gym_id);

CREATE UNIQUE INDEX pk_video_gym_class ON public.video_gym_class USING btree (class_id);

CREATE UNIQUE INDEX pk_video_gym_feed ON public.video_gym_feed USING btree (gym_id, video_id);

CREATE UNIQUE INDEX pk_video_gym_query ON public.video_gym_query USING btree (query_id);

CREATE UNIQUE INDEX pk_video_gym_reward ON public.video_gym_reward USING btree (reward_id);

CREATE UNIQUE INDEX rank_presets_gym_type_main_rank_num_order_sub_rank_num_orde_key ON public.rank_presets USING btree (gym_type, main_rank_num_order, sub_rank_num_order);

CREATE UNIQUE INDEX rank_presets_pkey ON public.rank_presets USING btree (preset_id);

CREATE UNIQUE INDEX stripe_webhook_events_pkey ON public.stripe_webhook_events USING btree (event_id);

CREATE UNIQUE INDEX unique_employee_user_gym ON public.gym_employees USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX unique_member_user_gym ON public.members USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

alter table "public"."class_history" add constraint "class_history_pkey" PRIMARY KEY using index "class_history_pkey";

alter table "public"."class_instance_exceptions" add constraint "class_instance_exceptions_pkey" PRIMARY KEY using index "class_instance_exceptions_pkey";

alter table "public"."class_range_exceptions" add constraint "class_range_exceptions_pkey" PRIMARY KEY using index "class_range_exceptions_pkey";

alter table "public"."gym_classes" add constraint "gym_classes_pkey" PRIMARY KEY using index "gym_classes_pkey";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_pkey" PRIMARY KEY using index "gym_discounts_unfiltered_pkey";

alter table "public"."gym_employees" add constraint "gym_employees_pkey" PRIMARY KEY using index "gym_employees_pkey";

alter table "public"."gym_history" add constraint "gym_history_pkey" PRIMARY KEY using index "gym_history_pkey";

alter table "public"."gym_ranks" add constraint "gym_ranks_pkey" PRIMARY KEY using index "gym_ranks_pkey";

alter table "public"."gym_rewards" add constraint "gym_rewards_pkey" PRIMARY KEY using index "gym_rewards_pkey";

alter table "public"."gyms" add constraint "gyms_pkey" PRIMARY KEY using index "gyms_pkey";

alter table "public"."member_activities" add constraint "member_activities_pkey" PRIMARY KEY using index "member_activities_pkey";

alter table "public"."member_attendance" add constraint "member_attendance_pkey" PRIMARY KEY using index "member_attendance_pkey";

alter table "public"."member_charges" add constraint "member_charges_pkey" PRIMARY KEY using index "member_charges_pkey";

alter table "public"."member_invoice_applied_discounts" add constraint "member_invoice_applied_discounts_pkey" PRIMARY KEY using index "member_invoice_applied_discounts_pkey";

alter table "public"."member_invoice_line_items" add constraint "member_invoice_line_items_pkey" PRIMARY KEY using index "member_invoice_line_items_pkey";

alter table "public"."member_invoices" add constraint "member_invoices_pkey" PRIMARY KEY using index "member_invoices_pkey";

alter table "public"."member_memberships_unfiltered" add constraint "member_memberships_unfiltered_pkey" PRIMARY KEY using index "member_memberships_unfiltered_pkey";

alter table "public"."member_reward_redemptions" add constraint "member_reward_redemptions_pkey" PRIMARY KEY using index "member_reward_redemptions_pkey";

alter table "public"."members" add constraint "members_pkey" PRIMARY KEY using index "members_pkey";

alter table "public"."membership_plan_prices_unfiltered" add constraint "membership_plan_prices_unfiltered_pkey" PRIMARY KEY using index "membership_plan_prices_unfiltered_pkey";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_pkey" PRIMARY KEY using index "membership_plans_unfiltered_pkey";

alter table "public"."rank_presets" add constraint "rank_presets_pkey" PRIMARY KEY using index "rank_presets_pkey";

alter table "public"."stripe_webhook_events" add constraint "stripe_webhook_events_pkey" PRIMARY KEY using index "stripe_webhook_events_pkey";

alter table "public"."video" add constraint "pk_video" PRIMARY KEY using index "pk_video";

alter table "public"."video_cost_log" add constraint "pk_video_cost_log" PRIMARY KEY using index "pk_video_cost_log";

alter table "public"."video_gym" add constraint "pk_video_gym" PRIMARY KEY using index "pk_video_gym";

alter table "public"."video_gym_class" add constraint "pk_video_gym_class" PRIMARY KEY using index "pk_video_gym_class";

alter table "public"."video_gym_feed" add constraint "pk_video_gym_feed" PRIMARY KEY using index "pk_video_gym_feed";

alter table "public"."video_gym_query" add constraint "pk_video_gym_query" PRIMARY KEY using index "pk_video_gym_query";

alter table "public"."video_gym_reward" add constraint "pk_video_gym_reward" PRIMARY KEY using index "pk_video_gym_reward";

alter table "public"."class_history" add constraint "class_history_class_history_id_gym_id_key" UNIQUE using index "class_history_class_history_id_gym_id_key";

alter table "public"."class_history" add constraint "class_history_duration_minutes_check" CHECK ((duration_minutes > 0)) not valid;

alter table "public"."class_history" validate constraint "class_history_duration_minutes_check";

alter table "public"."class_history" add constraint "fk_class_history_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."class_history" validate constraint "fk_class_history_class";

alter table "public"."class_history" add constraint "fk_class_history_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."class_history" validate constraint "fk_class_history_class_id";

alter table "public"."class_history" add constraint "fk_class_history_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."class_history" validate constraint "fk_class_history_gym";

alter table "public"."class_history" add constraint "fk_class_history_instructor" FOREIGN KEY (instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."class_history" validate constraint "fk_class_history_instructor";

alter table "public"."class_instance_exceptions" add constraint "class_instance_exceptions_class_id_original_date_key" UNIQUE using index "class_instance_exceptions_class_id_original_date_key";

alter table "public"."class_instance_exceptions" add constraint "class_instance_exceptions_new_duration_minutes_check" CHECK (((new_duration_minutes IS NULL) OR (new_duration_minutes > 0))) not valid;

alter table "public"."class_instance_exceptions" validate constraint "class_instance_exceptions_new_duration_minutes_check";

alter table "public"."class_instance_exceptions" add constraint "class_instance_exceptions_new_max_capacity_check" CHECK (((new_max_capacity IS NULL) OR (new_max_capacity > 0))) not valid;

alter table "public"."class_instance_exceptions" validate constraint "class_instance_exceptions_new_max_capacity_check";

alter table "public"."class_instance_exceptions" add constraint "fk_instance_exception_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."class_instance_exceptions" validate constraint "fk_instance_exception_class";

alter table "public"."class_instance_exceptions" add constraint "fk_instance_exception_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."class_instance_exceptions" validate constraint "fk_instance_exception_class_id";

alter table "public"."class_instance_exceptions" add constraint "fk_instance_exception_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."class_instance_exceptions" validate constraint "fk_instance_exception_gym";

alter table "public"."class_instance_exceptions" add constraint "fk_instance_exception_instructor" FOREIGN KEY (new_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."class_instance_exceptions" validate constraint "fk_instance_exception_instructor";

alter table "public"."class_range_exceptions" add constraint "class_range_exceptions_check" CHECK ((end_date >= start_date)) not valid;

alter table "public"."class_range_exceptions" validate constraint "class_range_exceptions_check";

alter table "public"."class_range_exceptions" add constraint "class_range_exceptions_check1" CHECK ((is_cancelled OR (new_instructor_id IS NOT NULL))) not valid;

alter table "public"."class_range_exceptions" validate constraint "class_range_exceptions_check1";

alter table "public"."class_range_exceptions" add constraint "fk_range_exception_class" FOREIGN KEY (class_id, gym_id) REFERENCES public.gym_classes(class_id, gym_id) not valid;

alter table "public"."class_range_exceptions" validate constraint "fk_range_exception_class";

alter table "public"."class_range_exceptions" add constraint "fk_range_exception_class_id" FOREIGN KEY (class_id) REFERENCES public.gym_classes(class_id) not valid;

alter table "public"."class_range_exceptions" validate constraint "fk_range_exception_class_id";

alter table "public"."class_range_exceptions" add constraint "fk_range_exception_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."class_range_exceptions" validate constraint "fk_range_exception_gym";

alter table "public"."class_range_exceptions" add constraint "fk_range_exception_instructor" FOREIGN KEY (new_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."class_range_exceptions" validate constraint "fk_range_exception_instructor";

alter table "public"."gym_classes" add constraint "fk_class_fri_instructor" FOREIGN KEY (fri_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_fri_instructor";

alter table "public"."gym_classes" add constraint "fk_class_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_gym";

alter table "public"."gym_classes" add constraint "fk_class_mon_instructor" FOREIGN KEY (mon_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_mon_instructor";

alter table "public"."gym_classes" add constraint "fk_class_sat_instructor" FOREIGN KEY (sat_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_sat_instructor";

alter table "public"."gym_classes" add constraint "fk_class_sun_instructor" FOREIGN KEY (sun_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_sun_instructor";

alter table "public"."gym_classes" add constraint "fk_class_thu_instructor" FOREIGN KEY (thu_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_thu_instructor";

alter table "public"."gym_classes" add constraint "fk_class_tue_instructor" FOREIGN KEY (tue_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_tue_instructor";

alter table "public"."gym_classes" add constraint "fk_class_wed_instructor" FOREIGN KEY (wed_instructor_id, gym_id) REFERENCES public.gym_employees(employee_id, gym_id) not valid;

alter table "public"."gym_classes" validate constraint "fk_class_wed_instructor";

alter table "public"."gym_classes" add constraint "gym_classes_check" CHECK (((end_date IS NULL) OR (end_date >= start_date))) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_check";

alter table "public"."gym_classes" add constraint "gym_classes_check1" CHECK (((recurring_unit <> 'weekly'::public.recurring_unit) OR sun OR mon OR tue OR wed OR thu OR fri OR sat)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_check1";

alter table "public"."gym_classes" add constraint "gym_classes_class_id_gym_id_key" UNIQUE using index "gym_classes_class_id_gym_id_key";

alter table "public"."gym_classes" add constraint "gym_classes_class_name_check" CHECK (((class_name)::text <> ''::text)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_class_name_check";

alter table "public"."gym_classes" add constraint "gym_classes_duration_minutes_check" CHECK ((duration_minutes > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_duration_minutes_check";

alter table "public"."gym_classes" add constraint "gym_classes_max_capacity_check" CHECK ((max_capacity > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_max_capacity_check";

alter table "public"."gym_classes" add constraint "gym_classes_points_worth_check" CHECK ((points_worth > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_points_worth_check";

alter table "public"."gym_classes" add constraint "gym_classes_recurring_interval_check" CHECK ((recurring_interval > 0)) not valid;

alter table "public"."gym_classes" validate constraint "gym_classes_recurring_interval_check";

alter table "public"."gym_discounts_unfiltered" add constraint "chk_duration_in_months" CHECK (((((duration)::text = 'repeating'::text) AND (duration_in_months IS NOT NULL)) OR (((duration)::text <> 'repeating'::text) AND (duration_in_months IS NULL)))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "chk_duration_in_months";

alter table "public"."gym_discounts_unfiltered" add constraint "chk_linked_discount_fields" CHECK (((((discount_type)::text = 'linked'::text) AND (membership_plan_id IS NOT NULL) AND (linked_discount_num IS NOT NULL) AND (dollar_off IS NOT NULL)) OR (((discount_type)::text <> 'linked'::text) AND (membership_plan_id IS NULL) AND (linked_discount_num IS NULL)))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "chk_linked_discount_fields";

alter table "public"."gym_discounts_unfiltered" add constraint "fk_discount_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "fk_discount_gym";

alter table "public"."gym_discounts_unfiltered" add constraint "fk_discount_plan" FOREIGN KEY (membership_plan_id) REFERENCES public.membership_plans_unfiltered(plan_id) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "fk_discount_plan";

alter table "public"."gym_discounts_unfiltered" add constraint "fk_discount_plan_gym" FOREIGN KEY (membership_plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "fk_discount_plan_gym";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_check" CHECK ((num_nonnulls(percentage_off, dollar_off) = 1)) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_id_gym_id_key" UNIQUE using index "gym_discounts_unfiltered_discount_id_gym_id_key";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_name_check" CHECK (((discount_name)::text <> ''::text)) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_name_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_discount_type_check" CHECK (((discount_type)::text = ANY ((ARRAY['preset'::character varying, 'custom'::character varying, 'linked'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_discount_type_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_dollar_off_check" CHECK ((dollar_off > 0)) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_dollar_off_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_duration_check" CHECK (((duration)::text = ANY ((ARRAY['once'::character varying, 'repeating'::character varying, 'forever'::character varying])::text[]))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_duration_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_duration_in_months_check" CHECK ((duration_in_months > 0)) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_duration_in_months_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key" UNIQUE using index "gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_linked_discount_num_check" CHECK ((linked_discount_num > 0)) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_linked_discount_num_check";

alter table "public"."gym_discounts_unfiltered" add constraint "gym_discounts_unfiltered_percentage_off_check" CHECK (((percentage_off > (0)::double precision) AND (percentage_off <= (100)::double precision))) not valid;

alter table "public"."gym_discounts_unfiltered" validate constraint "gym_discounts_unfiltered_percentage_off_check";

alter table "public"."gym_employees" add constraint "fk_employee_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_gym";

alter table "public"."gym_employees" add constraint "fk_employee_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."gym_employees" validate constraint "fk_employee_user";

alter table "public"."gym_employees" add constraint "gym_employees_employee_id_gym_id_key" UNIQUE using index "gym_employees_employee_id_gym_id_key";

alter table "public"."gym_employees" add constraint "gym_employees_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_first_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."gym_employees" validate constraint "gym_employees_last_name_check";

alter table "public"."gym_employees" add constraint "gym_employees_user_id_gym_id_key" UNIQUE using index "gym_employees_user_id_gym_id_key";

alter table "public"."gym_history" add constraint "fk_history_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_history" validate constraint "fk_history_gym";

alter table "public"."gym_history" add constraint "gym_history_became_active_check" CHECK ((became_active >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_became_active_check";

alter table "public"."gym_history" add constraint "gym_history_total_active_check" CHECK ((total_active >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_total_active_check";

alter table "public"."gym_history" add constraint "gym_history_total_inactive_check" CHECK ((total_inactive >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_total_inactive_check";

alter table "public"."gym_history" add constraint "gym_history_went_inactive_check" CHECK ((went_inactive >= 0)) not valid;

alter table "public"."gym_history" validate constraint "gym_history_went_inactive_check";

alter table "public"."gym_ranks" add constraint "fk_rank_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_ranks" validate constraint "fk_rank_gym";

alter table "public"."gym_ranks" add constraint "gym_ranks_classes_till_rankup_check" CHECK ((classes_till_rankup >= 0)) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_classes_till_rankup_check";

alter table "public"."gym_ranks" add constraint "gym_ranks_color_check" CHECK (((color IS NULL) OR ((color)::text ~ '^#[0-9A-Fa-f]{6}$'::text))) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_color_check";

alter table "public"."gym_ranks" add constraint "gym_ranks_gym_id_main_rank_num_order_sub_rank_num_order_key" UNIQUE using index "gym_ranks_gym_id_main_rank_num_order_sub_rank_num_order_key";

alter table "public"."gym_ranks" add constraint "gym_ranks_main_name_check" CHECK (((main_name)::text <> ''::text)) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_main_name_check";

alter table "public"."gym_ranks" add constraint "gym_ranks_main_rank_num_order_check" CHECK ((main_rank_num_order >= 0)) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_main_rank_num_order_check";

alter table "public"."gym_ranks" add constraint "gym_ranks_rank_id_gym_id_key" UNIQUE using index "gym_ranks_rank_id_gym_id_key";

alter table "public"."gym_ranks" add constraint "gym_ranks_sub_name_check" CHECK (((sub_name)::text <> ''::text)) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_sub_name_check";

alter table "public"."gym_ranks" add constraint "gym_ranks_sub_rank_num_order_check" CHECK ((sub_rank_num_order >= 0)) not valid;

alter table "public"."gym_ranks" validate constraint "gym_ranks_sub_rank_num_order_check";

alter table "public"."gym_rewards" add constraint "fk_reward_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_rewards" validate constraint "fk_reward_gym";

alter table "public"."gym_rewards" add constraint "gym_rewards_point_cost_check" CHECK ((point_cost > 0)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_point_cost_check";

alter table "public"."gym_rewards" add constraint "gym_rewards_reward_id_gym_id_key" UNIQUE using index "gym_rewards_reward_id_gym_id_key";

alter table "public"."gym_rewards" add constraint "gym_rewards_title_check" CHECK (((title)::text <> ''::text)) not valid;

alter table "public"."gym_rewards" validate constraint "gym_rewards_title_check";

alter table "public"."gyms" add constraint "gyms_gym_name_check" CHECK (((gym_name)::text <> ''::text)) not valid;

alter table "public"."gyms" validate constraint "gyms_gym_name_check";

alter table "public"."gyms" add constraint "gyms_stripe_account_id_key" UNIQUE using index "gyms_stripe_account_id_key";

alter table "public"."gyms" add constraint "gyms_stripe_onboarding_status_valid" CHECK ((stripe_onboarding_status = ANY (ARRAY['not_started'::text, 'pending'::text, 'complete'::text]))) not valid;

alter table "public"."gyms" validate constraint "gyms_stripe_onboarding_status_valid";

alter table "public"."gyms" add constraint "gyms_timezone_valid" CHECK (((now() AT TIME ZONE timezone) IS NOT NULL)) not valid;

alter table "public"."gyms" validate constraint "gyms_timezone_valid";

alter table "public"."member_activities" add constraint "fk_activity_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_activities" validate constraint "fk_activity_gym";

alter table "public"."member_activities" add constraint "fk_activity_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_activities" validate constraint "fk_activity_member_gym";

alter table "public"."member_attendance" add constraint "fk_attendance_class_history_gym" FOREIGN KEY (class_history_id, gym_id) REFERENCES public.class_history(class_history_id, gym_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_class_history_gym";

alter table "public"."member_attendance" add constraint "fk_attendance_class_history_id" FOREIGN KEY (class_history_id) REFERENCES public.class_history(class_history_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_class_history_id";

alter table "public"."member_attendance" add constraint "fk_attendance_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_gym";

alter table "public"."member_attendance" add constraint "fk_attendance_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_attendance" validate constraint "fk_attendance_member_gym";

alter table "public"."member_attendance" add constraint "member_attendance_member_id_class_history_id_key" UNIQUE using index "member_attendance_member_id_class_history_id_key";

alter table "public"."member_charges" add constraint "fk_charge_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_charges" validate constraint "fk_charge_gym";

alter table "public"."member_charges" add constraint "fk_charge_invoice" FOREIGN KEY (invoice_id) REFERENCES public.member_invoices(invoice_id) ON DELETE CASCADE not valid;

alter table "public"."member_charges" validate constraint "fk_charge_invoice";

alter table "public"."member_charges" add constraint "fk_charge_invoice_gym" FOREIGN KEY (invoice_id, gym_id) REFERENCES public.member_invoices(invoice_id, gym_id) not valid;

alter table "public"."member_charges" validate constraint "fk_charge_invoice_gym";

alter table "public"."member_charges" add constraint "fk_charge_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_charges" validate constraint "fk_charge_member_gym";

alter table "public"."member_charges" add constraint "fk_refund_parent" FOREIGN KEY (refunds_charge_id) REFERENCES public.member_charges(charge_id) not valid;

alter table "public"."member_charges" validate constraint "fk_refund_parent";

alter table "public"."member_charges" add constraint "member_charges_stripe_charge_id_key" UNIQUE using index "member_charges_stripe_charge_id_key";

alter table "public"."member_charges" add constraint "member_charges_stripe_refund_id_key" UNIQUE using index "member_charges_stripe_refund_id_key";

alter table "public"."member_charges" add constraint "payment_amount_nonneg" CHECK (((kind <> 'payment'::public.charge_kind) OR (amount >= 0))) not valid;

alter table "public"."member_charges" validate constraint "payment_amount_nonneg";

alter table "public"."member_charges" add constraint "payment_has_charge_id" CHECK (((kind <> 'payment'::public.charge_kind) OR (stripe_charge_id IS NOT NULL) OR ((payment_method_type)::text = 'cash'::text))) not valid;

alter table "public"."member_charges" validate constraint "payment_has_charge_id";

alter table "public"."member_charges" add constraint "payment_has_no_parent" CHECK (((kind <> 'payment'::public.charge_kind) OR (refunds_charge_id IS NULL))) not valid;

alter table "public"."member_charges" validate constraint "payment_has_no_parent";

alter table "public"."member_charges" add constraint "payment_has_no_refund_id" CHECK (((kind <> 'payment'::public.charge_kind) OR (stripe_refund_id IS NULL))) not valid;

alter table "public"."member_charges" validate constraint "payment_has_no_refund_id";

alter table "public"."member_charges" add constraint "refund_amount_nonpos" CHECK (((kind <> 'refund'::public.charge_kind) OR (amount <= 0))) not valid;

alter table "public"."member_charges" validate constraint "refund_amount_nonpos";

alter table "public"."member_charges" add constraint "refund_has_no_charge_id" CHECK (((kind <> 'refund'::public.charge_kind) OR (stripe_charge_id IS NULL))) not valid;

alter table "public"."member_charges" validate constraint "refund_has_no_charge_id";

alter table "public"."member_charges" add constraint "refund_has_parent" CHECK (((kind <> 'refund'::public.charge_kind) OR (refunds_charge_id IS NOT NULL))) not valid;

alter table "public"."member_charges" validate constraint "refund_has_parent";

alter table "public"."member_charges" add constraint "refund_has_refund_id" CHECK (((kind <> 'refund'::public.charge_kind) OR (stripe_refund_id IS NOT NULL))) not valid;

alter table "public"."member_charges" validate constraint "refund_has_refund_id";

alter table "public"."member_invoice_applied_discounts" add constraint "fk_applied_discount_discount_gym" FOREIGN KEY (discount_id, gym_id) REFERENCES public.gym_discounts_unfiltered(discount_id, gym_id) not valid;

alter table "public"."member_invoice_applied_discounts" validate constraint "fk_applied_discount_discount_gym";

alter table "public"."member_invoice_applied_discounts" add constraint "fk_applied_discount_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_invoice_applied_discounts" validate constraint "fk_applied_discount_gym";

alter table "public"."member_invoice_applied_discounts" add constraint "fk_applied_discount_invoice" FOREIGN KEY (invoice_id) REFERENCES public.member_invoices(invoice_id) ON DELETE CASCADE not valid;

alter table "public"."member_invoice_applied_discounts" validate constraint "fk_applied_discount_invoice";

alter table "public"."member_invoice_applied_discounts" add constraint "fk_applied_discount_invoice_gym" FOREIGN KEY (invoice_id, gym_id) REFERENCES public.member_invoices(invoice_id, gym_id) not valid;

alter table "public"."member_invoice_applied_discounts" validate constraint "fk_applied_discount_invoice_gym";

alter table "public"."member_invoice_applied_discounts" add constraint "member_invoice_applied_discounts_amount_off_check" CHECK ((amount_off >= 0)) not valid;

alter table "public"."member_invoice_applied_discounts" validate constraint "member_invoice_applied_discounts_amount_off_check";

alter table "public"."member_invoice_line_items" add constraint "custom_line_has_no_item_id" CHECK (((item_type <> 'custom'::public.line_item_type) OR (item_id IS NULL))) not valid;

alter table "public"."member_invoice_line_items" validate constraint "custom_line_has_no_item_id";

alter table "public"."member_invoice_line_items" add constraint "fk_line_item_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_invoice_line_items" validate constraint "fk_line_item_gym";

alter table "public"."member_invoice_line_items" add constraint "fk_line_item_invoice" FOREIGN KEY (invoice_id) REFERENCES public.member_invoices(invoice_id) ON DELETE CASCADE not valid;

alter table "public"."member_invoice_line_items" validate constraint "fk_line_item_invoice";

alter table "public"."member_invoice_line_items" add constraint "fk_line_item_invoice_gym" FOREIGN KEY (invoice_id, gym_id) REFERENCES public.member_invoices(invoice_id, gym_id) not valid;

alter table "public"."member_invoice_line_items" validate constraint "fk_line_item_invoice_gym";

alter table "public"."member_invoice_line_items" add constraint "fk_line_item_membership_gym" FOREIGN KEY (item_id, gym_id) REFERENCES public.member_memberships_unfiltered(item_id, gym_id) not valid;

alter table "public"."member_invoice_line_items" validate constraint "fk_line_item_membership_gym";

alter table "public"."member_invoice_line_items" add constraint "member_invoice_line_items_amount_check" CHECK ((amount >= 0)) not valid;

alter table "public"."member_invoice_line_items" validate constraint "member_invoice_line_items_amount_check";

alter table "public"."member_invoice_line_items" add constraint "member_invoice_line_items_name_check" CHECK (((name)::text <> ''::text)) not valid;

alter table "public"."member_invoice_line_items" validate constraint "member_invoice_line_items_name_check";

alter table "public"."member_invoice_line_items" add constraint "membership_line_has_item_id" CHECK (((item_type <> 'membership'::public.line_item_type) OR (item_id IS NOT NULL))) not valid;

alter table "public"."member_invoice_line_items" validate constraint "membership_line_has_item_id";

alter table "public"."member_invoices" add constraint "fk_invoice_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_invoices" validate constraint "fk_invoice_gym";

alter table "public"."member_invoices" add constraint "fk_invoice_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_invoices" validate constraint "fk_invoice_member_gym";

alter table "public"."member_invoices" add constraint "member_invoices_invoice_id_gym_id_key" UNIQUE using index "member_invoices_invoice_id_gym_id_key";

alter table "public"."member_invoices" add constraint "member_invoices_stripe_invoice_id_key" UNIQUE using index "member_invoices_stripe_invoice_id_key";

alter table "public"."member_invoices" add constraint "member_invoices_stripe_payment_intent_id_key" UNIQUE using index "member_invoices_stripe_payment_intent_id_key";

alter table "public"."member_invoices" add constraint "member_invoices_total_amount_check" CHECK ((total_amount >= 0)) not valid;

alter table "public"."member_invoices" validate constraint "member_invoices_total_amount_check";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_gym";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_member_gym";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_plan_gym";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_price" FOREIGN KEY (price_id) REFERENCES public.membership_plan_prices_unfiltered(price_id) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_price";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_price_plan" FOREIGN KEY (price_id, plan_id) REFERENCES public.membership_plan_prices_unfiltered(price_id, plan_id) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_price_plan";

alter table "public"."member_memberships_unfiltered" add constraint "member_memberships_unfiltered_item_id_gym_id_key" UNIQUE using index "member_memberships_unfiltered_item_id_gym_id_key";

alter table "public"."member_memberships_unfiltered" add constraint "member_memberships_unfiltered_item_id_member_id_key" UNIQUE using index "member_memberships_unfiltered_item_id_member_id_key";

alter table "public"."member_memberships_unfiltered" add constraint "member_memberships_unfiltered_total_price_check" CHECK ((total_price >= 0)) not valid;

alter table "public"."member_memberships_unfiltered" validate constraint "member_memberships_unfiltered_total_price_check";

alter table "public"."member_reward_redemptions" add constraint "fk_redemption_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_reward_redemptions" validate constraint "fk_redemption_gym";

alter table "public"."member_reward_redemptions" add constraint "fk_redemption_member_gym" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_reward_redemptions" validate constraint "fk_redemption_member_gym";

alter table "public"."member_reward_redemptions" add constraint "fk_redemption_reward" FOREIGN KEY (reward_id) REFERENCES public.gym_rewards(reward_id) not valid;

alter table "public"."member_reward_redemptions" validate constraint "fk_redemption_reward";

alter table "public"."member_reward_redemptions" add constraint "fk_redemption_reward_gym" FOREIGN KEY (reward_id, gym_id) REFERENCES public.gym_rewards(reward_id, gym_id) not valid;

alter table "public"."member_reward_redemptions" validate constraint "fk_redemption_reward_gym";

alter table "public"."member_reward_redemptions" add constraint "member_reward_redemptions_point_cost_check" CHECK ((point_cost >= 0)) not valid;

alter table "public"."member_reward_redemptions" validate constraint "member_reward_redemptions_point_cost_check";

alter table "public"."members" add constraint "fk_member_current_rank" FOREIGN KEY (current_rank_id, gym_id) REFERENCES public.gym_ranks(rank_id, gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_current_rank";

alter table "public"."members" add constraint "fk_member_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_gym";

alter table "public"."members" add constraint "fk_member_linked_account" FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_linked_account";

alter table "public"."members" add constraint "fk_member_linked_discount" FOREIGN KEY (linked_discount_id) REFERENCES public.gym_discounts_unfiltered(discount_id) not valid;

alter table "public"."members" validate constraint "fk_member_linked_discount";

alter table "public"."members" add constraint "fk_member_linked_discount_gym" FOREIGN KEY (linked_discount_id, gym_id) REFERENCES public.gym_discounts_unfiltered(discount_id, gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_linked_discount_gym";

alter table "public"."members" add constraint "fk_member_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."members" validate constraint "fk_member_user";

alter table "public"."members" add constraint "freeze_dates_must_be_paired" CHECK ((((freeze_start_date IS NULL) AND (freeze_end_date IS NULL)) OR ((freeze_start_date IS NOT NULL) AND (freeze_end_date IS NOT NULL)))) not valid;

alter table "public"."members" validate constraint "freeze_dates_must_be_paired";

alter table "public"."members" add constraint "linked_account_no_stripe" CHECK (((account_linked_to_id IS NULL) OR ((stripe_sub_id_month IS NULL) AND (freeze_start_date IS NULL) AND (freeze_end_date IS NULL) AND (payment_type IS NULL) AND (card_brand IS NULL) AND (card_last_four IS NULL) AND (card_exp_month IS NULL) AND (card_exp_year IS NULL)))) not valid;

alter table "public"."members" validate constraint "linked_account_no_stripe";

alter table "public"."members" add constraint "members_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."members" validate constraint "members_first_name_check";

alter table "public"."members" add constraint "members_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."members" validate constraint "members_last_name_check";

alter table "public"."members" add constraint "members_member_id_gym_id_key" UNIQUE using index "members_member_id_gym_id_key";

alter table "public"."members" add constraint "members_points_balance_check" CHECK ((points_balance >= 0)) not valid;

alter table "public"."members" validate constraint "members_points_balance_check";

alter table "public"."members" add constraint "members_total_monthly_recurring_price_check" CHECK ((total_monthly_recurring_price >= 0)) not valid;

alter table "public"."members" validate constraint "members_total_monthly_recurring_price_check";

alter table "public"."membership_plan_prices_unfiltered" add constraint "fk_plan_price_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plan_prices_unfiltered" validate constraint "fk_plan_price_gym";

alter table "public"."membership_plan_prices_unfiltered" add constraint "fk_plan_price_plan" FOREIGN KEY (plan_id) REFERENCES public.membership_plans_unfiltered(plan_id) not valid;

alter table "public"."membership_plan_prices_unfiltered" validate constraint "fk_plan_price_plan";

alter table "public"."membership_plan_prices_unfiltered" add constraint "fk_plan_price_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans_unfiltered(plan_id, gym_id) not valid;

alter table "public"."membership_plan_prices_unfiltered" validate constraint "fk_plan_price_plan_gym";

alter table "public"."membership_plan_prices_unfiltered" add constraint "membership_plan_prices_unfiltered_price_check" CHECK ((price >= 0)) not valid;

alter table "public"."membership_plan_prices_unfiltered" validate constraint "membership_plan_prices_unfiltered_price_check";

alter table "public"."membership_plan_prices_unfiltered" add constraint "membership_plan_prices_unfiltered_price_id_plan_id_key" UNIQUE using index "membership_plan_prices_unfiltered_price_id_plan_id_key";

alter table "public"."membership_plans_unfiltered" add constraint "duration_both_or_neither" CHECK (((duration_amount IS NULL) = (duration_unit IS NULL))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "duration_both_or_neither";

alter table "public"."membership_plans_unfiltered" add constraint "duration_required_unless_class_count" CHECK ((((duration_amount IS NOT NULL) AND (duration_unit IS NOT NULL)) OR (((plan_type)::text <> 'recurring'::text) AND (class_count IS NOT NULL)))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "duration_required_unless_class_count";

alter table "public"."membership_plans_unfiltered" add constraint "fk_plan_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "fk_plan_gym";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_class_count_check" CHECK ((class_count > 0)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_class_count_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_amount_check" CHECK ((duration_amount > 0)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_amount_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_duration_unit_check" CHECK (((duration_unit)::text = ANY ((ARRAY['week'::character varying, 'month'::character varying, 'year'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_duration_unit_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_id_gym_id_key" UNIQUE using index "membership_plans_unfiltered_plan_id_gym_id_key";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_name_check" CHECK (((plan_name)::text <> ''::text)) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_name_check";

alter table "public"."membership_plans_unfiltered" add constraint "membership_plans_unfiltered_plan_type_check" CHECK (((plan_type)::text = ANY ((ARRAY['trial'::character varying, 'recurring'::character varying, 'one_time'::character varying])::text[]))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "membership_plans_unfiltered_plan_type_check";

alter table "public"."membership_plans_unfiltered" add constraint "recurring_must_be_monthly" CHECK ((((plan_type)::text <> 'recurring'::text) OR (((duration_unit)::text = 'month'::text) AND (duration_amount = 1)))) not valid;

alter table "public"."membership_plans_unfiltered" validate constraint "recurring_must_be_monthly";

alter table "public"."rank_presets" add constraint "rank_presets_classes_till_rankup_check" CHECK ((classes_till_rankup >= 0)) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_classes_till_rankup_check";

alter table "public"."rank_presets" add constraint "rank_presets_color_check" CHECK (((color IS NULL) OR ((color)::text ~ '^#[0-9A-Fa-f]{6}$'::text))) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_color_check";

alter table "public"."rank_presets" add constraint "rank_presets_gym_type_main_rank_num_order_sub_rank_num_orde_key" UNIQUE using index "rank_presets_gym_type_main_rank_num_order_sub_rank_num_orde_key";

alter table "public"."rank_presets" add constraint "rank_presets_main_name_check" CHECK (((main_name)::text <> ''::text)) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_main_name_check";

alter table "public"."rank_presets" add constraint "rank_presets_main_rank_num_order_check" CHECK ((main_rank_num_order >= 0)) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_main_rank_num_order_check";

alter table "public"."rank_presets" add constraint "rank_presets_sub_name_check" CHECK (((sub_name)::text <> ''::text)) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_sub_name_check";

alter table "public"."rank_presets" add constraint "rank_presets_sub_rank_num_order_check" CHECK ((sub_rank_num_order >= 0)) not valid;

alter table "public"."rank_presets" validate constraint "rank_presets_sub_rank_num_order_check";

alter table "public"."stripe_webhook_events" add constraint "fk_webhook_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."stripe_webhook_events" validate constraint "fk_webhook_gym";

alter table "public"."video" add constraint "video_disciplines_is_array" CHECK ((jsonb_typeof(disciplines) = 'array'::text)) not valid;

alter table "public"."video" validate constraint "video_disciplines_is_array";

alter table "public"."video" add constraint "video_id_format" CHECK ((video_id ~ '^[A-Za-z0-9_-]+$'::text)) not valid;

alter table "public"."video" validate constraint "video_id_format";

alter table "public"."video" add constraint "video_relevance_index_nonneg" CHECK ((relevance_index >= 0)) not valid;

alter table "public"."video" validate constraint "video_relevance_index_nonneg";

alter table "public"."video" add constraint "video_source_queries_is_array" CHECK ((jsonb_typeof(source_queries) = 'array'::text)) not valid;

alter table "public"."video" validate constraint "video_source_queries_is_array";

alter table "public"."video_cost_log" add constraint "fk_video_cost_log_gym" FOREIGN KEY (gym_id) REFERENCES public.video_gym(gym_id) ON DELETE SET NULL not valid;

alter table "public"."video_cost_log" validate constraint "fk_video_cost_log_gym";

alter table "public"."video_gym" add constraint "video_gym_avoid_desc_len" CHECK ((char_length(avoid_desc) >= 2)) not valid;

alter table "public"."video_gym" validate constraint "video_gym_avoid_desc_len";

alter table "public"."video_gym" add constraint "video_gym_id_format" CHECK ((gym_id ~ '^[a-z0-9][a-z0-9_]*$'::text)) not valid;

alter table "public"."video_gym" validate constraint "video_gym_id_format";

alter table "public"."video_gym" add constraint "video_gym_theme_nonempty" CHECK ((theme <> ''::text)) not valid;

alter table "public"."video_gym" validate constraint "video_gym_theme_nonempty";

alter table "public"."video_gym" add constraint "video_gym_type_nonempty" CHECK (((jsonb_typeof(gym_type) = 'array'::text) AND (jsonb_array_length(gym_type) >= 1))) not valid;

alter table "public"."video_gym" validate constraint "video_gym_type_nonempty";

alter table "public"."video_gym" add constraint "video_gym_videos_desc_len" CHECK ((char_length(videos_desc) >= 2)) not valid;

alter table "public"."video_gym" validate constraint "video_gym_videos_desc_len";

alter table "public"."video_gym_class" add constraint "fk_video_gym_class_gym" FOREIGN KEY (gym_id) REFERENCES public.video_gym(gym_id) ON DELETE CASCADE not valid;

alter table "public"."video_gym_class" validate constraint "fk_video_gym_class_gym";

alter table "public"."video_gym_class" add constraint "video_gym_class_description_nonempty" CHECK ((description <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_description_nonempty";

alter table "public"."video_gym_class" add constraint "video_gym_class_image_url_nonempty" CHECK ((image_url <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_image_url_nonempty";

alter table "public"."video_gym_class" add constraint "video_gym_class_instructor_bio_nonempty" CHECK ((instructor_bio <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_instructor_bio_nonempty";

alter table "public"."video_gym_class" add constraint "video_gym_class_instructor_image_url_nonempty" CHECK ((instructor_image_url <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_instructor_image_url_nonempty";

alter table "public"."video_gym_class" add constraint "video_gym_class_instructor_name_nonempty" CHECK ((instructor_name <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_instructor_name_nonempty";

alter table "public"."video_gym_class" add constraint "video_gym_class_name_nonempty" CHECK ((name <> ''::text)) not valid;

alter table "public"."video_gym_class" validate constraint "video_gym_class_name_nonempty";

alter table "public"."video_gym_feed" add constraint "fk_video_gym_feed_gym" FOREIGN KEY (gym_id) REFERENCES public.video_gym(gym_id) ON DELETE CASCADE not valid;

alter table "public"."video_gym_feed" validate constraint "fk_video_gym_feed_gym";

alter table "public"."video_gym_feed" add constraint "fk_video_gym_feed_video" FOREIGN KEY (video_id) REFERENCES public.video(video_id) ON DELETE CASCADE not valid;

alter table "public"."video_gym_feed" validate constraint "fk_video_gym_feed_video";

alter table "public"."video_gym_query" add constraint "fk_video_gym_query_gym" FOREIGN KEY (gym_id) REFERENCES public.video_gym(gym_id) ON DELETE CASCADE not valid;

alter table "public"."video_gym_query" validate constraint "fk_video_gym_query_gym";

alter table "public"."video_gym_query" add constraint "video_gym_query_nonempty" CHECK ((query <> ''::text)) not valid;

alter table "public"."video_gym_query" validate constraint "video_gym_query_nonempty";

alter table "public"."video_gym_reward" add constraint "fk_video_gym_reward_gym" FOREIGN KEY (gym_id) REFERENCES public.video_gym(gym_id) ON DELETE CASCADE not valid;

alter table "public"."video_gym_reward" validate constraint "fk_video_gym_reward_gym";

alter table "public"."video_gym_reward" add constraint "video_gym_reward_image_url_nonempty" CHECK ((image_url <> ''::text)) not valid;

alter table "public"."video_gym_reward" validate constraint "video_gym_reward_image_url_nonempty";

alter table "public"."video_gym_reward" add constraint "video_gym_reward_points_cost_nonneg" CHECK ((points_cost >= 0)) not valid;

alter table "public"."video_gym_reward" validate constraint "video_gym_reward_points_cost_nonneg";

alter table "public"."video_gym_reward" add constraint "video_gym_reward_price_label_nonempty" CHECK ((price_label <> ''::text)) not valid;

alter table "public"."video_gym_reward" validate constraint "video_gym_reward_price_label_nonempty";

alter table "public"."video_gym_reward" add constraint "video_gym_reward_title_nonempty" CHECK ((title <> ''::text)) not valid;

alter table "public"."video_gym_reward" validate constraint "video_gym_reward_title_nonempty";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_discount_ids_gym_match()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.check_linked_discount_type()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships_unfiltered mm
        WHERE mm.member_id = NEW.member_id
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
        WHERE mm.member_id = NEW.member_id
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
        FROM membership_plans_unfiltered
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
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships_unfiltered mm
            WHERE mm.member_id = NEW.member_id
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

CREATE OR REPLACE FUNCTION public.enforce_linked_account_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        -- This member is becoming a child — ensure it is not already a parent
        IF EXISTS (
            SELECT 1 FROM members
            WHERE account_linked_to_id = NEW.member_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.member_id;
        END IF;

        -- Ensure the target parent is not itself a child
        IF EXISTS (
            SELECT 1 FROM members
            WHERE member_id = NEW.account_linked_to_id
              AND account_linked_to_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Cannot link to account % — it is already linked to another account',
                NEW.account_linked_to_id;
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
$function$
;

create or replace view "public"."gym_discounts" as  SELECT discount_id,
    gym_id,
    discount_name,
    discount_type,
    percentage_off,
    dollar_off,
    membership_plan_id,
    linked_discount_num,
    duration,
    duration_in_months,
    is_deleted,
    stripe_coupon_id,
    created_at
   FROM public.gym_discounts_unfiltered
  WHERE (stripe_coupon_id IS NOT NULL);


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
    linked_discount_id,
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
    discount_ids,
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
    mm.discount_ids,
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


create or replace view "public"."membership_plan_prices" as  SELECT price_id,
    plan_id,
    gym_id,
    stripe_price_id,
    price,
    is_active,
    created_at
   FROM public.membership_plan_prices_unfiltered
  WHERE (stripe_price_id IS NOT NULL);


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
    created_at
   FROM public.membership_plans_unfiltered
  WHERE (stripe_product_id IS NOT NULL);


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

CREATE OR REPLACE FUNCTION public.prevent_stripe_customer_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (member_id: %)', OLD.member_id;
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
    IF OLD.stripe_item_id IS NOT NULL AND NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_user_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (member_id: %)', OLD.member_id;
    END IF;
    RETURN NEW;
END;
$function$
;

grant delete on table "public"."class_history" to "anon";

grant insert on table "public"."class_history" to "anon";

grant references on table "public"."class_history" to "anon";

grant select on table "public"."class_history" to "anon";

grant trigger on table "public"."class_history" to "anon";

grant truncate on table "public"."class_history" to "anon";

grant update on table "public"."class_history" to "anon";

grant delete on table "public"."class_history" to "authenticated";

grant insert on table "public"."class_history" to "authenticated";

grant references on table "public"."class_history" to "authenticated";

grant select on table "public"."class_history" to "authenticated";

grant trigger on table "public"."class_history" to "authenticated";

grant truncate on table "public"."class_history" to "authenticated";

grant delete on table "public"."class_history" to "service_role";

grant insert on table "public"."class_history" to "service_role";

grant references on table "public"."class_history" to "service_role";

grant select on table "public"."class_history" to "service_role";

grant trigger on table "public"."class_history" to "service_role";

grant truncate on table "public"."class_history" to "service_role";

grant update on table "public"."class_history" to "service_role";

grant delete on table "public"."class_instance_exceptions" to "anon";

grant insert on table "public"."class_instance_exceptions" to "anon";

grant references on table "public"."class_instance_exceptions" to "anon";

grant select on table "public"."class_instance_exceptions" to "anon";

grant trigger on table "public"."class_instance_exceptions" to "anon";

grant truncate on table "public"."class_instance_exceptions" to "anon";

grant update on table "public"."class_instance_exceptions" to "anon";

grant delete on table "public"."class_instance_exceptions" to "authenticated";

grant insert on table "public"."class_instance_exceptions" to "authenticated";

grant references on table "public"."class_instance_exceptions" to "authenticated";

grant select on table "public"."class_instance_exceptions" to "authenticated";

grant trigger on table "public"."class_instance_exceptions" to "authenticated";

grant truncate on table "public"."class_instance_exceptions" to "authenticated";

grant update on table "public"."class_instance_exceptions" to "authenticated";

grant delete on table "public"."class_instance_exceptions" to "service_role";

grant insert on table "public"."class_instance_exceptions" to "service_role";

grant references on table "public"."class_instance_exceptions" to "service_role";

grant select on table "public"."class_instance_exceptions" to "service_role";

grant trigger on table "public"."class_instance_exceptions" to "service_role";

grant truncate on table "public"."class_instance_exceptions" to "service_role";

grant update on table "public"."class_instance_exceptions" to "service_role";

grant delete on table "public"."class_range_exceptions" to "anon";

grant insert on table "public"."class_range_exceptions" to "anon";

grant references on table "public"."class_range_exceptions" to "anon";

grant select on table "public"."class_range_exceptions" to "anon";

grant trigger on table "public"."class_range_exceptions" to "anon";

grant truncate on table "public"."class_range_exceptions" to "anon";

grant update on table "public"."class_range_exceptions" to "anon";

grant delete on table "public"."class_range_exceptions" to "authenticated";

grant insert on table "public"."class_range_exceptions" to "authenticated";

grant references on table "public"."class_range_exceptions" to "authenticated";

grant select on table "public"."class_range_exceptions" to "authenticated";

grant trigger on table "public"."class_range_exceptions" to "authenticated";

grant truncate on table "public"."class_range_exceptions" to "authenticated";

grant update on table "public"."class_range_exceptions" to "authenticated";

grant delete on table "public"."class_range_exceptions" to "service_role";

grant insert on table "public"."class_range_exceptions" to "service_role";

grant references on table "public"."class_range_exceptions" to "service_role";

grant select on table "public"."class_range_exceptions" to "service_role";

grant trigger on table "public"."class_range_exceptions" to "service_role";

grant truncate on table "public"."class_range_exceptions" to "service_role";

grant update on table "public"."class_range_exceptions" to "service_role";

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

grant delete on table "public"."gym_discounts_unfiltered" to "anon";

grant insert on table "public"."gym_discounts_unfiltered" to "anon";

grant references on table "public"."gym_discounts_unfiltered" to "anon";

grant select on table "public"."gym_discounts_unfiltered" to "anon";

grant trigger on table "public"."gym_discounts_unfiltered" to "anon";

grant truncate on table "public"."gym_discounts_unfiltered" to "anon";

grant update on table "public"."gym_discounts_unfiltered" to "anon";

grant delete on table "public"."gym_discounts_unfiltered" to "authenticated";

grant references on table "public"."gym_discounts_unfiltered" to "authenticated";

grant select on table "public"."gym_discounts_unfiltered" to "authenticated";

grant trigger on table "public"."gym_discounts_unfiltered" to "authenticated";

grant truncate on table "public"."gym_discounts_unfiltered" to "authenticated";

grant delete on table "public"."gym_discounts_unfiltered" to "service_role";

grant insert on table "public"."gym_discounts_unfiltered" to "service_role";

grant references on table "public"."gym_discounts_unfiltered" to "service_role";

grant select on table "public"."gym_discounts_unfiltered" to "service_role";

grant trigger on table "public"."gym_discounts_unfiltered" to "service_role";

grant truncate on table "public"."gym_discounts_unfiltered" to "service_role";

grant update on table "public"."gym_discounts_unfiltered" to "service_role";

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

grant delete on table "public"."gym_ranks" to "anon";

grant insert on table "public"."gym_ranks" to "anon";

grant references on table "public"."gym_ranks" to "anon";

grant select on table "public"."gym_ranks" to "anon";

grant trigger on table "public"."gym_ranks" to "anon";

grant truncate on table "public"."gym_ranks" to "anon";

grant update on table "public"."gym_ranks" to "anon";

grant delete on table "public"."gym_ranks" to "authenticated";

grant insert on table "public"."gym_ranks" to "authenticated";

grant references on table "public"."gym_ranks" to "authenticated";

grant select on table "public"."gym_ranks" to "authenticated";

grant trigger on table "public"."gym_ranks" to "authenticated";

grant truncate on table "public"."gym_ranks" to "authenticated";

grant update on table "public"."gym_ranks" to "authenticated";

grant delete on table "public"."gym_ranks" to "service_role";

grant insert on table "public"."gym_ranks" to "service_role";

grant references on table "public"."gym_ranks" to "service_role";

grant select on table "public"."gym_ranks" to "service_role";

grant trigger on table "public"."gym_ranks" to "service_role";

grant truncate on table "public"."gym_ranks" to "service_role";

grant update on table "public"."gym_ranks" to "service_role";

grant delete on table "public"."gym_rewards" to "anon";

grant insert on table "public"."gym_rewards" to "anon";

grant references on table "public"."gym_rewards" to "anon";

grant select on table "public"."gym_rewards" to "anon";

grant trigger on table "public"."gym_rewards" to "anon";

grant truncate on table "public"."gym_rewards" to "anon";

grant update on table "public"."gym_rewards" to "anon";

grant delete on table "public"."gym_rewards" to "authenticated";

grant insert on table "public"."gym_rewards" to "authenticated";

grant references on table "public"."gym_rewards" to "authenticated";

grant select on table "public"."gym_rewards" to "authenticated";

grant trigger on table "public"."gym_rewards" to "authenticated";

grant truncate on table "public"."gym_rewards" to "authenticated";

grant update on table "public"."gym_rewards" to "authenticated";

grant delete on table "public"."gym_rewards" to "service_role";

grant insert on table "public"."gym_rewards" to "service_role";

grant references on table "public"."gym_rewards" to "service_role";

grant select on table "public"."gym_rewards" to "service_role";

grant trigger on table "public"."gym_rewards" to "service_role";

grant truncate on table "public"."gym_rewards" to "service_role";

grant update on table "public"."gym_rewards" to "service_role";

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

grant delete on table "public"."member_activities" to "anon";

grant insert on table "public"."member_activities" to "anon";

grant references on table "public"."member_activities" to "anon";

grant select on table "public"."member_activities" to "anon";

grant trigger on table "public"."member_activities" to "anon";

grant truncate on table "public"."member_activities" to "anon";

grant update on table "public"."member_activities" to "anon";

grant delete on table "public"."member_activities" to "authenticated";

grant insert on table "public"."member_activities" to "authenticated";

grant references on table "public"."member_activities" to "authenticated";

grant select on table "public"."member_activities" to "authenticated";

grant trigger on table "public"."member_activities" to "authenticated";

grant truncate on table "public"."member_activities" to "authenticated";

grant delete on table "public"."member_activities" to "service_role";

grant insert on table "public"."member_activities" to "service_role";

grant references on table "public"."member_activities" to "service_role";

grant select on table "public"."member_activities" to "service_role";

grant trigger on table "public"."member_activities" to "service_role";

grant truncate on table "public"."member_activities" to "service_role";

grant update on table "public"."member_activities" to "service_role";

grant delete on table "public"."member_attendance" to "anon";

grant insert on table "public"."member_attendance" to "anon";

grant references on table "public"."member_attendance" to "anon";

grant select on table "public"."member_attendance" to "anon";

grant trigger on table "public"."member_attendance" to "anon";

grant truncate on table "public"."member_attendance" to "anon";

grant update on table "public"."member_attendance" to "anon";

grant delete on table "public"."member_attendance" to "authenticated";

grant insert on table "public"."member_attendance" to "authenticated";

grant references on table "public"."member_attendance" to "authenticated";

grant select on table "public"."member_attendance" to "authenticated";

grant trigger on table "public"."member_attendance" to "authenticated";

grant truncate on table "public"."member_attendance" to "authenticated";

grant delete on table "public"."member_attendance" to "service_role";

grant insert on table "public"."member_attendance" to "service_role";

grant references on table "public"."member_attendance" to "service_role";

grant select on table "public"."member_attendance" to "service_role";

grant trigger on table "public"."member_attendance" to "service_role";

grant truncate on table "public"."member_attendance" to "service_role";

grant update on table "public"."member_attendance" to "service_role";

grant delete on table "public"."member_charges" to "anon";

grant insert on table "public"."member_charges" to "anon";

grant references on table "public"."member_charges" to "anon";

grant select on table "public"."member_charges" to "anon";

grant trigger on table "public"."member_charges" to "anon";

grant truncate on table "public"."member_charges" to "anon";

grant update on table "public"."member_charges" to "anon";

grant delete on table "public"."member_charges" to "authenticated";

grant references on table "public"."member_charges" to "authenticated";

grant select on table "public"."member_charges" to "authenticated";

grant trigger on table "public"."member_charges" to "authenticated";

grant truncate on table "public"."member_charges" to "authenticated";

grant delete on table "public"."member_charges" to "service_role";

grant insert on table "public"."member_charges" to "service_role";

grant references on table "public"."member_charges" to "service_role";

grant select on table "public"."member_charges" to "service_role";

grant trigger on table "public"."member_charges" to "service_role";

grant truncate on table "public"."member_charges" to "service_role";

grant update on table "public"."member_charges" to "service_role";

grant delete on table "public"."member_invoice_applied_discounts" to "anon";

grant insert on table "public"."member_invoice_applied_discounts" to "anon";

grant references on table "public"."member_invoice_applied_discounts" to "anon";

grant select on table "public"."member_invoice_applied_discounts" to "anon";

grant trigger on table "public"."member_invoice_applied_discounts" to "anon";

grant truncate on table "public"."member_invoice_applied_discounts" to "anon";

grant update on table "public"."member_invoice_applied_discounts" to "anon";

grant delete on table "public"."member_invoice_applied_discounts" to "authenticated";

grant references on table "public"."member_invoice_applied_discounts" to "authenticated";

grant select on table "public"."member_invoice_applied_discounts" to "authenticated";

grant trigger on table "public"."member_invoice_applied_discounts" to "authenticated";

grant truncate on table "public"."member_invoice_applied_discounts" to "authenticated";

grant delete on table "public"."member_invoice_applied_discounts" to "service_role";

grant insert on table "public"."member_invoice_applied_discounts" to "service_role";

grant references on table "public"."member_invoice_applied_discounts" to "service_role";

grant select on table "public"."member_invoice_applied_discounts" to "service_role";

grant trigger on table "public"."member_invoice_applied_discounts" to "service_role";

grant truncate on table "public"."member_invoice_applied_discounts" to "service_role";

grant update on table "public"."member_invoice_applied_discounts" to "service_role";

grant delete on table "public"."member_invoice_line_items" to "anon";

grant insert on table "public"."member_invoice_line_items" to "anon";

grant references on table "public"."member_invoice_line_items" to "anon";

grant select on table "public"."member_invoice_line_items" to "anon";

grant trigger on table "public"."member_invoice_line_items" to "anon";

grant truncate on table "public"."member_invoice_line_items" to "anon";

grant update on table "public"."member_invoice_line_items" to "anon";

grant delete on table "public"."member_invoice_line_items" to "authenticated";

grant references on table "public"."member_invoice_line_items" to "authenticated";

grant select on table "public"."member_invoice_line_items" to "authenticated";

grant trigger on table "public"."member_invoice_line_items" to "authenticated";

grant truncate on table "public"."member_invoice_line_items" to "authenticated";

grant delete on table "public"."member_invoice_line_items" to "service_role";

grant insert on table "public"."member_invoice_line_items" to "service_role";

grant references on table "public"."member_invoice_line_items" to "service_role";

grant select on table "public"."member_invoice_line_items" to "service_role";

grant trigger on table "public"."member_invoice_line_items" to "service_role";

grant truncate on table "public"."member_invoice_line_items" to "service_role";

grant update on table "public"."member_invoice_line_items" to "service_role";

grant delete on table "public"."member_invoices" to "anon";

grant insert on table "public"."member_invoices" to "anon";

grant references on table "public"."member_invoices" to "anon";

grant select on table "public"."member_invoices" to "anon";

grant trigger on table "public"."member_invoices" to "anon";

grant truncate on table "public"."member_invoices" to "anon";

grant update on table "public"."member_invoices" to "anon";

grant delete on table "public"."member_invoices" to "authenticated";

grant references on table "public"."member_invoices" to "authenticated";

grant select on table "public"."member_invoices" to "authenticated";

grant trigger on table "public"."member_invoices" to "authenticated";

grant truncate on table "public"."member_invoices" to "authenticated";

grant delete on table "public"."member_invoices" to "service_role";

grant insert on table "public"."member_invoices" to "service_role";

grant references on table "public"."member_invoices" to "service_role";

grant select on table "public"."member_invoices" to "service_role";

grant trigger on table "public"."member_invoices" to "service_role";

grant truncate on table "public"."member_invoices" to "service_role";

grant update on table "public"."member_invoices" to "service_role";

grant delete on table "public"."member_memberships_unfiltered" to "anon";

grant insert on table "public"."member_memberships_unfiltered" to "anon";

grant references on table "public"."member_memberships_unfiltered" to "anon";

grant select on table "public"."member_memberships_unfiltered" to "anon";

grant trigger on table "public"."member_memberships_unfiltered" to "anon";

grant truncate on table "public"."member_memberships_unfiltered" to "anon";

grant update on table "public"."member_memberships_unfiltered" to "anon";

grant delete on table "public"."member_memberships_unfiltered" to "authenticated";

grant insert on table "public"."member_memberships_unfiltered" to "authenticated";

grant references on table "public"."member_memberships_unfiltered" to "authenticated";

grant select on table "public"."member_memberships_unfiltered" to "authenticated";

grant trigger on table "public"."member_memberships_unfiltered" to "authenticated";

grant truncate on table "public"."member_memberships_unfiltered" to "authenticated";

grant delete on table "public"."member_memberships_unfiltered" to "service_role";

grant insert on table "public"."member_memberships_unfiltered" to "service_role";

grant references on table "public"."member_memberships_unfiltered" to "service_role";

grant select on table "public"."member_memberships_unfiltered" to "service_role";

grant trigger on table "public"."member_memberships_unfiltered" to "service_role";

grant truncate on table "public"."member_memberships_unfiltered" to "service_role";

grant update on table "public"."member_memberships_unfiltered" to "service_role";

grant delete on table "public"."member_reward_redemptions" to "anon";

grant insert on table "public"."member_reward_redemptions" to "anon";

grant references on table "public"."member_reward_redemptions" to "anon";

grant select on table "public"."member_reward_redemptions" to "anon";

grant trigger on table "public"."member_reward_redemptions" to "anon";

grant truncate on table "public"."member_reward_redemptions" to "anon";

grant update on table "public"."member_reward_redemptions" to "anon";

grant delete on table "public"."member_reward_redemptions" to "authenticated";

grant insert on table "public"."member_reward_redemptions" to "authenticated";

grant references on table "public"."member_reward_redemptions" to "authenticated";

grant select on table "public"."member_reward_redemptions" to "authenticated";

grant trigger on table "public"."member_reward_redemptions" to "authenticated";

grant truncate on table "public"."member_reward_redemptions" to "authenticated";

grant delete on table "public"."member_reward_redemptions" to "service_role";

grant insert on table "public"."member_reward_redemptions" to "service_role";

grant references on table "public"."member_reward_redemptions" to "service_role";

grant select on table "public"."member_reward_redemptions" to "service_role";

grant trigger on table "public"."member_reward_redemptions" to "service_role";

grant truncate on table "public"."member_reward_redemptions" to "service_role";

grant update on table "public"."member_reward_redemptions" to "service_role";

grant delete on table "public"."members" to "anon";

grant insert on table "public"."members" to "anon";

grant references on table "public"."members" to "anon";

grant select on table "public"."members" to "anon";

grant trigger on table "public"."members" to "anon";

grant truncate on table "public"."members" to "anon";

grant update on table "public"."members" to "anon";

grant delete on table "public"."members" to "authenticated";

grant references on table "public"."members" to "authenticated";

grant select on table "public"."members" to "authenticated";

grant trigger on table "public"."members" to "authenticated";

grant truncate on table "public"."members" to "authenticated";

grant update on table "public"."members" to "authenticated";

grant delete on table "public"."members" to "service_role";

grant insert on table "public"."members" to "service_role";

grant references on table "public"."members" to "service_role";

grant select on table "public"."members" to "service_role";

grant trigger on table "public"."members" to "service_role";

grant truncate on table "public"."members" to "service_role";

grant update on table "public"."members" to "service_role";

grant delete on table "public"."membership_plan_prices_unfiltered" to "anon";

grant insert on table "public"."membership_plan_prices_unfiltered" to "anon";

grant references on table "public"."membership_plan_prices_unfiltered" to "anon";

grant select on table "public"."membership_plan_prices_unfiltered" to "anon";

grant trigger on table "public"."membership_plan_prices_unfiltered" to "anon";

grant truncate on table "public"."membership_plan_prices_unfiltered" to "anon";

grant update on table "public"."membership_plan_prices_unfiltered" to "anon";

grant delete on table "public"."membership_plan_prices_unfiltered" to "authenticated";

grant references on table "public"."membership_plan_prices_unfiltered" to "authenticated";

grant select on table "public"."membership_plan_prices_unfiltered" to "authenticated";

grant trigger on table "public"."membership_plan_prices_unfiltered" to "authenticated";

grant truncate on table "public"."membership_plan_prices_unfiltered" to "authenticated";

grant delete on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant insert on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant references on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant select on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant trigger on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant truncate on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant update on table "public"."membership_plan_prices_unfiltered" to "service_role";

grant delete on table "public"."membership_plans_unfiltered" to "anon";

grant insert on table "public"."membership_plans_unfiltered" to "anon";

grant references on table "public"."membership_plans_unfiltered" to "anon";

grant select on table "public"."membership_plans_unfiltered" to "anon";

grant trigger on table "public"."membership_plans_unfiltered" to "anon";

grant truncate on table "public"."membership_plans_unfiltered" to "anon";

grant update on table "public"."membership_plans_unfiltered" to "anon";

grant delete on table "public"."membership_plans_unfiltered" to "authenticated";

grant insert on table "public"."membership_plans_unfiltered" to "authenticated";

grant references on table "public"."membership_plans_unfiltered" to "authenticated";

grant select on table "public"."membership_plans_unfiltered" to "authenticated";

grant trigger on table "public"."membership_plans_unfiltered" to "authenticated";

grant truncate on table "public"."membership_plans_unfiltered" to "authenticated";

grant delete on table "public"."membership_plans_unfiltered" to "service_role";

grant insert on table "public"."membership_plans_unfiltered" to "service_role";

grant references on table "public"."membership_plans_unfiltered" to "service_role";

grant select on table "public"."membership_plans_unfiltered" to "service_role";

grant trigger on table "public"."membership_plans_unfiltered" to "service_role";

grant truncate on table "public"."membership_plans_unfiltered" to "service_role";

grant update on table "public"."membership_plans_unfiltered" to "service_role";

grant delete on table "public"."rank_presets" to "anon";

grant insert on table "public"."rank_presets" to "anon";

grant references on table "public"."rank_presets" to "anon";

grant select on table "public"."rank_presets" to "anon";

grant trigger on table "public"."rank_presets" to "anon";

grant truncate on table "public"."rank_presets" to "anon";

grant update on table "public"."rank_presets" to "anon";

grant delete on table "public"."rank_presets" to "authenticated";

grant insert on table "public"."rank_presets" to "authenticated";

grant references on table "public"."rank_presets" to "authenticated";

grant select on table "public"."rank_presets" to "authenticated";

grant trigger on table "public"."rank_presets" to "authenticated";

grant truncate on table "public"."rank_presets" to "authenticated";

grant update on table "public"."rank_presets" to "authenticated";

grant delete on table "public"."rank_presets" to "service_role";

grant insert on table "public"."rank_presets" to "service_role";

grant references on table "public"."rank_presets" to "service_role";

grant select on table "public"."rank_presets" to "service_role";

grant trigger on table "public"."rank_presets" to "service_role";

grant truncate on table "public"."rank_presets" to "service_role";

grant update on table "public"."rank_presets" to "service_role";

grant delete on table "public"."stripe_webhook_events" to "anon";

grant insert on table "public"."stripe_webhook_events" to "anon";

grant references on table "public"."stripe_webhook_events" to "anon";

grant select on table "public"."stripe_webhook_events" to "anon";

grant trigger on table "public"."stripe_webhook_events" to "anon";

grant truncate on table "public"."stripe_webhook_events" to "anon";

grant update on table "public"."stripe_webhook_events" to "anon";

grant delete on table "public"."stripe_webhook_events" to "service_role";

grant insert on table "public"."stripe_webhook_events" to "service_role";

grant references on table "public"."stripe_webhook_events" to "service_role";

grant select on table "public"."stripe_webhook_events" to "service_role";

grant trigger on table "public"."stripe_webhook_events" to "service_role";

grant truncate on table "public"."stripe_webhook_events" to "service_role";

grant update on table "public"."stripe_webhook_events" to "service_role";

grant delete on table "public"."video" to "anon";

grant insert on table "public"."video" to "anon";

grant references on table "public"."video" to "anon";

grant select on table "public"."video" to "anon";

grant trigger on table "public"."video" to "anon";

grant truncate on table "public"."video" to "anon";

grant update on table "public"."video" to "anon";

grant delete on table "public"."video" to "authenticated";

grant insert on table "public"."video" to "authenticated";

grant references on table "public"."video" to "authenticated";

grant select on table "public"."video" to "authenticated";

grant trigger on table "public"."video" to "authenticated";

grant truncate on table "public"."video" to "authenticated";

grant update on table "public"."video" to "authenticated";

grant delete on table "public"."video" to "service_role";

grant insert on table "public"."video" to "service_role";

grant references on table "public"."video" to "service_role";

grant select on table "public"."video" to "service_role";

grant trigger on table "public"."video" to "service_role";

grant truncate on table "public"."video" to "service_role";

grant update on table "public"."video" to "service_role";

grant delete on table "public"."video_cost_log" to "anon";

grant insert on table "public"."video_cost_log" to "anon";

grant references on table "public"."video_cost_log" to "anon";

grant select on table "public"."video_cost_log" to "anon";

grant trigger on table "public"."video_cost_log" to "anon";

grant truncate on table "public"."video_cost_log" to "anon";

grant update on table "public"."video_cost_log" to "anon";

grant delete on table "public"."video_cost_log" to "authenticated";

grant insert on table "public"."video_cost_log" to "authenticated";

grant references on table "public"."video_cost_log" to "authenticated";

grant select on table "public"."video_cost_log" to "authenticated";

grant trigger on table "public"."video_cost_log" to "authenticated";

grant truncate on table "public"."video_cost_log" to "authenticated";

grant delete on table "public"."video_cost_log" to "service_role";

grant insert on table "public"."video_cost_log" to "service_role";

grant references on table "public"."video_cost_log" to "service_role";

grant select on table "public"."video_cost_log" to "service_role";

grant trigger on table "public"."video_cost_log" to "service_role";

grant truncate on table "public"."video_cost_log" to "service_role";

grant update on table "public"."video_cost_log" to "service_role";

grant delete on table "public"."video_gym" to "anon";

grant insert on table "public"."video_gym" to "anon";

grant references on table "public"."video_gym" to "anon";

grant select on table "public"."video_gym" to "anon";

grant trigger on table "public"."video_gym" to "anon";

grant truncate on table "public"."video_gym" to "anon";

grant update on table "public"."video_gym" to "anon";

grant delete on table "public"."video_gym" to "authenticated";

grant insert on table "public"."video_gym" to "authenticated";

grant references on table "public"."video_gym" to "authenticated";

grant select on table "public"."video_gym" to "authenticated";

grant trigger on table "public"."video_gym" to "authenticated";

grant truncate on table "public"."video_gym" to "authenticated";

grant update on table "public"."video_gym" to "authenticated";

grant delete on table "public"."video_gym" to "service_role";

grant insert on table "public"."video_gym" to "service_role";

grant references on table "public"."video_gym" to "service_role";

grant select on table "public"."video_gym" to "service_role";

grant trigger on table "public"."video_gym" to "service_role";

grant truncate on table "public"."video_gym" to "service_role";

grant update on table "public"."video_gym" to "service_role";

grant delete on table "public"."video_gym_class" to "anon";

grant insert on table "public"."video_gym_class" to "anon";

grant references on table "public"."video_gym_class" to "anon";

grant select on table "public"."video_gym_class" to "anon";

grant trigger on table "public"."video_gym_class" to "anon";

grant truncate on table "public"."video_gym_class" to "anon";

grant update on table "public"."video_gym_class" to "anon";

grant delete on table "public"."video_gym_class" to "authenticated";

grant insert on table "public"."video_gym_class" to "authenticated";

grant references on table "public"."video_gym_class" to "authenticated";

grant select on table "public"."video_gym_class" to "authenticated";

grant trigger on table "public"."video_gym_class" to "authenticated";

grant truncate on table "public"."video_gym_class" to "authenticated";

grant update on table "public"."video_gym_class" to "authenticated";

grant delete on table "public"."video_gym_class" to "service_role";

grant insert on table "public"."video_gym_class" to "service_role";

grant references on table "public"."video_gym_class" to "service_role";

grant select on table "public"."video_gym_class" to "service_role";

grant trigger on table "public"."video_gym_class" to "service_role";

grant truncate on table "public"."video_gym_class" to "service_role";

grant update on table "public"."video_gym_class" to "service_role";

grant delete on table "public"."video_gym_feed" to "anon";

grant insert on table "public"."video_gym_feed" to "anon";

grant references on table "public"."video_gym_feed" to "anon";

grant select on table "public"."video_gym_feed" to "anon";

grant trigger on table "public"."video_gym_feed" to "anon";

grant truncate on table "public"."video_gym_feed" to "anon";

grant update on table "public"."video_gym_feed" to "anon";

grant delete on table "public"."video_gym_feed" to "authenticated";

grant insert on table "public"."video_gym_feed" to "authenticated";

grant references on table "public"."video_gym_feed" to "authenticated";

grant select on table "public"."video_gym_feed" to "authenticated";

grant trigger on table "public"."video_gym_feed" to "authenticated";

grant truncate on table "public"."video_gym_feed" to "authenticated";

grant update on table "public"."video_gym_feed" to "authenticated";

grant delete on table "public"."video_gym_feed" to "service_role";

grant insert on table "public"."video_gym_feed" to "service_role";

grant references on table "public"."video_gym_feed" to "service_role";

grant select on table "public"."video_gym_feed" to "service_role";

grant trigger on table "public"."video_gym_feed" to "service_role";

grant truncate on table "public"."video_gym_feed" to "service_role";

grant update on table "public"."video_gym_feed" to "service_role";

grant delete on table "public"."video_gym_query" to "anon";

grant insert on table "public"."video_gym_query" to "anon";

grant references on table "public"."video_gym_query" to "anon";

grant select on table "public"."video_gym_query" to "anon";

grant trigger on table "public"."video_gym_query" to "anon";

grant truncate on table "public"."video_gym_query" to "anon";

grant update on table "public"."video_gym_query" to "anon";

grant delete on table "public"."video_gym_query" to "authenticated";

grant insert on table "public"."video_gym_query" to "authenticated";

grant references on table "public"."video_gym_query" to "authenticated";

grant select on table "public"."video_gym_query" to "authenticated";

grant trigger on table "public"."video_gym_query" to "authenticated";

grant truncate on table "public"."video_gym_query" to "authenticated";

grant update on table "public"."video_gym_query" to "authenticated";

grant delete on table "public"."video_gym_query" to "service_role";

grant insert on table "public"."video_gym_query" to "service_role";

grant references on table "public"."video_gym_query" to "service_role";

grant select on table "public"."video_gym_query" to "service_role";

grant trigger on table "public"."video_gym_query" to "service_role";

grant truncate on table "public"."video_gym_query" to "service_role";

grant update on table "public"."video_gym_query" to "service_role";

grant delete on table "public"."video_gym_reward" to "anon";

grant insert on table "public"."video_gym_reward" to "anon";

grant references on table "public"."video_gym_reward" to "anon";

grant select on table "public"."video_gym_reward" to "anon";

grant trigger on table "public"."video_gym_reward" to "anon";

grant truncate on table "public"."video_gym_reward" to "anon";

grant update on table "public"."video_gym_reward" to "anon";

grant delete on table "public"."video_gym_reward" to "authenticated";

grant insert on table "public"."video_gym_reward" to "authenticated";

grant references on table "public"."video_gym_reward" to "authenticated";

grant select on table "public"."video_gym_reward" to "authenticated";

grant trigger on table "public"."video_gym_reward" to "authenticated";

grant truncate on table "public"."video_gym_reward" to "authenticated";

grant update on table "public"."video_gym_reward" to "authenticated";

grant delete on table "public"."video_gym_reward" to "service_role";

grant insert on table "public"."video_gym_reward" to "service_role";

grant references on table "public"."video_gym_reward" to "service_role";

grant select on table "public"."video_gym_reward" to "service_role";

grant trigger on table "public"."video_gym_reward" to "service_role";

grant truncate on table "public"."video_gym_reward" to "service_role";

grant update on table "public"."video_gym_reward" to "service_role";


  create policy "Gym staff can insert class history"
  on "public"."class_history"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view class history"
  on "public"."class_history"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = class_history.gym_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym employees can view instance exceptions"
  on "public"."class_instance_exceptions"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert instance exceptions"
  on "public"."class_instance_exceptions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update instance exceptions"
  on "public"."class_instance_exceptions"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view instance exceptions"
  on "public"."class_instance_exceptions"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = class_instance_exceptions.gym_id) AND (members.user_id = auth.uid())))));



  create policy "Gym employees can view range exceptions"
  on "public"."class_range_exceptions"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert range exceptions"
  on "public"."class_range_exceptions"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update range exceptions"
  on "public"."class_range_exceptions"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view range exceptions"
  on "public"."class_range_exceptions"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = class_range_exceptions.gym_id) AND (members.user_id = auth.uid())))));



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
   FROM public.members
  WHERE ((members.gym_id = gym_classes.gym_id) AND (members.user_id = auth.uid())))));



  create policy "Gym staff can view discounts"
  on "public"."gym_discounts_unfiltered"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "hide_incomplete_stripe_records"
  on "public"."gym_discounts_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_coupon_id IS NOT NULL));



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
with check ((public.is_gym_admin_or_owner(gym_id) OR ((employee_type = 'owner'::public.employee_type) AND (user_id = auth.uid()) AND (NOT public.gym_has_owner(gym_id)))));



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



  create policy "Gym employees can view ranks"
  on "public"."gym_ranks"
  as permissive
  for select
  to public
using (public.is_gym_employee(gym_id));



  create policy "Gym staff can insert ranks"
  on "public"."gym_ranks"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update ranks"
  on "public"."gym_ranks"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view their gym's ranks"
  on "public"."gym_ranks"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = gym_ranks.gym_id) AND (members.user_id = auth.uid())))));



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



  create policy "Members can view active rewards"
  on "public"."gym_rewards"
  as permissive
  for select
  to public
using (((is_active = true) AND (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = gym_rewards.gym_id) AND (members.user_id = auth.uid()))))));



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



  create policy "Gym staff can insert activities"
  on "public"."member_activities"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view activities"
  on "public"."member_activities"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_activities.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can insert attendance"
  on "public"."member_attendance"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view attendance"
  on "public"."member_attendance"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_attendance.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view charges"
  on "public"."member_charges"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_charges.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view applied discounts"
  on "public"."member_invoice_applied_discounts"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM (public.member_invoices inv
     JOIN public.members m ON ((m.member_id = inv.member_id)))
  WHERE ((inv.invoice_id = member_invoice_applied_discounts.invoice_id) AND (m.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view invoice line items"
  on "public"."member_invoice_line_items"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM (public.member_invoices inv
     JOIN public.members m ON ((m.member_id = inv.member_id)))
  WHERE ((inv.invoice_id = member_invoice_line_items.invoice_id) AND (m.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view invoices"
  on "public"."member_invoices"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_invoices.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can view memberships"
  on "public"."member_memberships_unfiltered"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view own memberships"
  on "public"."member_memberships_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_memberships_unfiltered.member_id) AND (members.user_id = auth.uid())))));



  create policy "hide_incomplete_stripe_records"
  on "public"."member_memberships_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_item_id IS NOT NULL));



  create policy "Members and gym staff can insert redemptions"
  on "public"."member_reward_redemptions"
  as permissive
  for insert
  to authenticated
with check ((public.is_gym_admin_or_owner(gym_id) OR (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_reward_redemptions.member_id) AND (members.user_id = auth.uid()) AND (members.gym_id = member_reward_redemptions.gym_id))))));



  create policy "Users and gym staff can view reward redemptions"
  on "public"."member_reward_redemptions"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_reward_redemptions.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can insert members"
  on "public"."members"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can update members"
  on "public"."members"
  as permissive
  for update
  to public
using (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)))
with check (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Users and gym staff can view members"
  on "public"."members"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR public.is_gym_admin_or_owner(gym_id)));



  create policy "Gym staff can view plan prices"
  on "public"."membership_plan_prices_unfiltered"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view plan prices"
  on "public"."membership_plan_prices_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = membership_plan_prices_unfiltered.gym_id) AND (members.user_id = auth.uid())))));



  create policy "hide_incomplete_stripe_records"
  on "public"."membership_plan_prices_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_price_id IS NOT NULL));



  create policy "Gym staff can view plans"
  on "public"."membership_plans_unfiltered"
  as permissive
  for select
  to public
using (public.is_gym_admin_or_owner(gym_id));



  create policy "Members can view gym plans"
  on "public"."membership_plans_unfiltered"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.gym_id = membership_plans_unfiltered.gym_id) AND (members.user_id = auth.uid())))));



  create policy "hide_incomplete_stripe_records"
  on "public"."membership_plans_unfiltered"
  as restrictive
  for select
  to authenticated
using ((stripe_product_id IS NOT NULL));



  create policy "Authenticated can view rank presets"
  on "public"."rank_presets"
  as permissive
  for select
  to authenticated
using (true);



  create policy "Public can read videos"
  on "public"."video"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video cost log"
  on "public"."video_cost_log"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video gyms"
  on "public"."video_gym"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video gym classes"
  on "public"."video_gym_class"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video gym feed"
  on "public"."video_gym_feed"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video gym queries"
  on "public"."video_gym_query"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "Public can read video gym rewards"
  on "public"."video_gym_reward"
  as permissive
  for select
  to anon, authenticated
using (true);


CREATE TRIGGER trg_enforce_linked_discount_sequence_delete BEFORE DELETE ON public.gym_discounts_unfiltered FOR EACH ROW WHEN (((old.discount_type)::text = 'linked'::text)) EXECUTE FUNCTION public.enforce_linked_discount_sequence();

CREATE TRIGGER trg_enforce_linked_discount_sequence_insert_update BEFORE INSERT OR UPDATE OF linked_discount_num ON public.gym_discounts_unfiltered FOR EACH ROW WHEN (((new.discount_type)::text = 'linked'::text)) EXECUTE FUNCTION public.enforce_linked_discount_sequence();

CREATE TRIGGER trg_check_discount_ids_gym_match BEFORE INSERT OR UPDATE OF discount_ids ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_discount_ids_gym_match();

CREATE TRIGGER trg_prevent_cancel_date_overwrite BEFORE UPDATE OF cancel_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_cancel_date_overwrite();

CREATE TRIGGER trg_prevent_plan_id_overwrite BEFORE UPDATE OF plan_id ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_plan_id_overwrite();

CREATE TRIGGER trg_prevent_stripe_item_id_overwrite BEFORE UPDATE OF stripe_item_id ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_item_id_overwrite();

CREATE TRIGGER trg_recurring_chronological_start_date BEFORE INSERT ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_chronological_start_date();

CREATE TRIGGER trg_recurring_no_active_memberships BEFORE INSERT ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_active_memberships();

CREATE TRIGGER trg_recurring_no_end_date BEFORE INSERT OR UPDATE OF end_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_end_date();

CREATE TRIGGER trg_recurring_no_overlapping_daterange BEFORE INSERT OR UPDATE OF cancel_date ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.check_recurring_no_overlapping_daterange();

CREATE TRIGGER trg_check_linked_discount_type BEFORE INSERT OR UPDATE OF linked_discount_id ON public.members FOR EACH ROW EXECUTE FUNCTION public.check_linked_discount_type();

CREATE TRIGGER trg_enforce_linked_account_hierarchy BEFORE INSERT OR UPDATE OF account_linked_to_id ON public.members FOR EACH ROW EXECUTE FUNCTION public.enforce_linked_account_hierarchy();

CREATE TRIGGER trg_prevent_stripe_customer_id_overwrite BEFORE UPDATE OF stripe_customer_id ON public.members FOR EACH ROW EXECUTE FUNCTION public.prevent_stripe_customer_id_overwrite();

CREATE TRIGGER trg_prevent_user_id_overwrite BEFORE UPDATE OF user_id ON public.members FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_overwrite();


