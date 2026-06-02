create extension if not exists "btree_gist" with schema "public";

create type "public"."employee_type" as enum ('owner', 'admin', 'trainer');

create type "public"."gym_type" as enum ('bjj', 'mma', 'generic');

create type "public"."member_active_type" as enum ('active', 'inactive');

create type "public"."member_status_type" as enum ('trial', 'full', 'disabled');

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
    "is_rank_enabled" boolean not null default true
      );


alter table "public"."gyms" enable row level security;


  create table "public"."member_active" (
    "active_id" uuid not null default extensions.uuid_generate_v4(),
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "active_type" public.member_active_type not null,
    "start_date" date not null,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_active" enable row level security;


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


  create table "public"."member_reward_redemptions" (
    "redemption_id" uuid not null default extensions.uuid_generate_v4(),
    "gym_id" uuid not null,
    "member_id" uuid not null,
    "reward_id" uuid not null,
    "point_cost" integer not null,
    "redeemed_at" timestamp with time zone not null default now()
      );


alter table "public"."member_reward_redemptions" enable row level security;


  create table "public"."member_status" (
    "status_id" uuid not null default extensions.uuid_generate_v4(),
    "member_id" uuid not null,
    "gym_id" uuid not null,
    "status_type" public.member_status_type not null,
    "start_date" date not null,
    "end_date" date,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."member_status" enable row level security;


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
    "current_rank_id" uuid
      );


alter table "public"."members" enable row level security;


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

CREATE INDEX idx_class_history_class_time ON public.class_history USING btree (class_id, occurred_at DESC);

CREATE INDEX idx_member_active_member_current ON public.member_active USING btree (member_id, start_date DESC);

CREATE INDEX idx_member_attendance_class_history ON public.member_attendance USING btree (class_history_id);

CREATE INDEX idx_member_attendance_member_gym ON public.member_attendance USING btree (member_id, gym_id);

CREATE INDEX idx_member_reward_redemptions_member_gym_time ON public.member_reward_redemptions USING btree (member_id, gym_id, redeemed_at DESC);

CREATE INDEX idx_member_status_member_current ON public.member_status USING btree (member_id, start_date DESC);

CREATE INDEX idx_video_cost_log_gym ON public.video_cost_log USING btree (gym_id);

CREATE INDEX idx_video_disciplines ON public.video USING gin (disciplines);

CREATE INDEX idx_video_gym_class_gym ON public.video_gym_class USING btree (gym_id);

CREATE INDEX idx_video_gym_feed_serve ON public.video_gym_feed USING btree (gym_id, status);

CREATE INDEX idx_video_gym_query_gym ON public.video_gym_query USING btree (gym_id);

CREATE INDEX idx_video_gym_reward_gym ON public.video_gym_reward USING btree (gym_id);

CREATE INDEX idx_video_tag ON public.video USING btree (tag);

select 1; 
-- CREATE INDEX member_active_member_id_daterange_excl ON public.member_active USING gist (member_id, daterange(start_date, end_date, '[]'::text));

CREATE UNIQUE INDEX member_active_pkey ON public.member_active USING btree (active_id);

CREATE UNIQUE INDEX member_activities_pkey ON public.member_activities USING btree (activity_id);

CREATE UNIQUE INDEX member_attendance_member_id_class_history_id_key ON public.member_attendance USING btree (member_id, class_history_id);

CREATE UNIQUE INDEX member_attendance_pkey ON public.member_attendance USING btree (log_id);

CREATE UNIQUE INDEX member_reward_redemptions_pkey ON public.member_reward_redemptions USING btree (redemption_id);

select 1; 
-- CREATE INDEX member_status_member_id_daterange_excl ON public.member_status USING gist (member_id, daterange(start_date, end_date, '[]'::text));

CREATE UNIQUE INDEX member_status_pkey ON public.member_status USING btree (status_id);

CREATE UNIQUE INDEX members_member_id_gym_id_key ON public.members USING btree (member_id, gym_id);

CREATE UNIQUE INDEX members_pkey ON public.members USING btree (member_id);

CREATE UNIQUE INDEX pk_video ON public.video USING btree (video_id);

CREATE UNIQUE INDEX pk_video_cost_log ON public.video_cost_log USING btree (entry_id);

CREATE UNIQUE INDEX pk_video_gym ON public.video_gym USING btree (gym_id);

CREATE UNIQUE INDEX pk_video_gym_class ON public.video_gym_class USING btree (class_id);

CREATE UNIQUE INDEX pk_video_gym_feed ON public.video_gym_feed USING btree (gym_id, video_id);

CREATE UNIQUE INDEX pk_video_gym_query ON public.video_gym_query USING btree (query_id);

CREATE UNIQUE INDEX pk_video_gym_reward ON public.video_gym_reward USING btree (reward_id);

CREATE UNIQUE INDEX rank_presets_gym_type_main_rank_num_order_sub_rank_num_orde_key ON public.rank_presets USING btree (gym_type, main_rank_num_order, sub_rank_num_order);

CREATE UNIQUE INDEX rank_presets_pkey ON public.rank_presets USING btree (preset_id);

CREATE UNIQUE INDEX unique_employee_user_gym ON public.gym_employees USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX unique_member_user_gym ON public.members USING btree (user_id, gym_id) WHERE (user_id IS NOT NULL);

alter table "public"."class_history" add constraint "class_history_pkey" PRIMARY KEY using index "class_history_pkey";

alter table "public"."class_instance_exceptions" add constraint "class_instance_exceptions_pkey" PRIMARY KEY using index "class_instance_exceptions_pkey";

alter table "public"."class_range_exceptions" add constraint "class_range_exceptions_pkey" PRIMARY KEY using index "class_range_exceptions_pkey";

alter table "public"."gym_classes" add constraint "gym_classes_pkey" PRIMARY KEY using index "gym_classes_pkey";

alter table "public"."gym_employees" add constraint "gym_employees_pkey" PRIMARY KEY using index "gym_employees_pkey";

alter table "public"."gym_history" add constraint "gym_history_pkey" PRIMARY KEY using index "gym_history_pkey";

alter table "public"."gym_ranks" add constraint "gym_ranks_pkey" PRIMARY KEY using index "gym_ranks_pkey";

alter table "public"."gym_rewards" add constraint "gym_rewards_pkey" PRIMARY KEY using index "gym_rewards_pkey";

alter table "public"."gyms" add constraint "gyms_pkey" PRIMARY KEY using index "gyms_pkey";

alter table "public"."member_active" add constraint "member_active_pkey" PRIMARY KEY using index "member_active_pkey";

alter table "public"."member_activities" add constraint "member_activities_pkey" PRIMARY KEY using index "member_activities_pkey";

alter table "public"."member_attendance" add constraint "member_attendance_pkey" PRIMARY KEY using index "member_attendance_pkey";

alter table "public"."member_reward_redemptions" add constraint "member_reward_redemptions_pkey" PRIMARY KEY using index "member_reward_redemptions_pkey";

alter table "public"."member_status" add constraint "member_status_pkey" PRIMARY KEY using index "member_status_pkey";

alter table "public"."members" add constraint "members_pkey" PRIMARY KEY using index "members_pkey";

alter table "public"."rank_presets" add constraint "rank_presets_pkey" PRIMARY KEY using index "rank_presets_pkey";

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

alter table "public"."gyms" add constraint "gyms_timezone_valid" CHECK (((now() AT TIME ZONE timezone) IS NOT NULL)) not valid;

alter table "public"."gyms" validate constraint "gyms_timezone_valid";

alter table "public"."member_active" add constraint "fk_member_active_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_active" validate constraint "fk_member_active_gym";

alter table "public"."member_active" add constraint "fk_member_active_member" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_active" validate constraint "fk_member_active_member";

alter table "public"."member_active" add constraint "member_active_check" CHECK (((end_date IS NULL) OR (end_date >= start_date))) not valid;

alter table "public"."member_active" validate constraint "member_active_check";

alter table "public"."member_active" add constraint "member_active_member_id_daterange_excl" EXCLUDE USING gist (member_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);

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

alter table "public"."member_status" add constraint "fk_member_status_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_status" validate constraint "fk_member_status_gym";

alter table "public"."member_status" add constraint "fk_member_status_member" FOREIGN KEY (member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;

alter table "public"."member_status" validate constraint "fk_member_status_member";

alter table "public"."member_status" add constraint "member_status_check" CHECK (((end_date IS NULL) OR (end_date >= start_date))) not valid;

alter table "public"."member_status" validate constraint "member_status_check";

alter table "public"."member_status" add constraint "member_status_member_id_daterange_excl" EXCLUDE USING gist (member_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);

alter table "public"."members" add constraint "fk_member_current_rank" FOREIGN KEY (current_rank_id, gym_id) REFERENCES public.gym_ranks(rank_id, gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_current_rank";

alter table "public"."members" add constraint "fk_member_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."members" validate constraint "fk_member_gym";

alter table "public"."members" add constraint "fk_member_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."members" validate constraint "fk_member_user";

alter table "public"."members" add constraint "members_first_name_check" CHECK (((first_name)::text <> ''::text)) not valid;

alter table "public"."members" validate constraint "members_first_name_check";

alter table "public"."members" add constraint "members_last_name_check" CHECK (((last_name)::text <> ''::text)) not valid;

alter table "public"."members" validate constraint "members_last_name_check";

alter table "public"."members" add constraint "members_member_id_gym_id_key" UNIQUE using index "members_member_id_gym_id_key";

alter table "public"."members" add constraint "members_points_balance_check" CHECK ((points_balance >= 0)) not valid;

alter table "public"."members" validate constraint "members_points_balance_check";

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

create or replace view "public"."members_with_status" as  SELECT member_id,
    user_id,
    gym_id,
    created_at,
    last_class,
    first_name,
    last_name,
    email,
    points_balance,
    current_rank_id,
    COALESCE(( SELECT (s.status_type)::text AS status_type
           FROM public.member_status s
          WHERE ((s.member_id = m.member_id) AND (s.start_date <= CURRENT_DATE) AND ((s.end_date IS NULL) OR (s.end_date >= CURRENT_DATE)))
         LIMIT 1), 'inactive'::text) AS status,
    COALESCE(( SELECT (a.active_type = 'active'::public.member_active_type)
           FROM public.member_active a
          WHERE ((a.member_id = m.member_id) AND (a.start_date <= CURRENT_DATE) AND ((a.end_date IS NULL) OR (a.end_date >= CURRENT_DATE)))
         LIMIT 1), false) AS active,
        CASE
            WHEN (last_class IS NULL) THEN NULL::integer
            ELSE (CURRENT_DATE - (last_class)::date)
        END AS last_class_days_ago
   FROM public.members m;


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

grant delete on table "public"."member_active" to "anon";

grant insert on table "public"."member_active" to "anon";

grant references on table "public"."member_active" to "anon";

grant select on table "public"."member_active" to "anon";

grant trigger on table "public"."member_active" to "anon";

grant truncate on table "public"."member_active" to "anon";

grant update on table "public"."member_active" to "anon";

grant delete on table "public"."member_active" to "authenticated";

grant insert on table "public"."member_active" to "authenticated";

grant references on table "public"."member_active" to "authenticated";

grant select on table "public"."member_active" to "authenticated";

grant trigger on table "public"."member_active" to "authenticated";

grant truncate on table "public"."member_active" to "authenticated";

grant update on table "public"."member_active" to "authenticated";

grant delete on table "public"."member_active" to "service_role";

grant insert on table "public"."member_active" to "service_role";

grant references on table "public"."member_active" to "service_role";

grant select on table "public"."member_active" to "service_role";

grant trigger on table "public"."member_active" to "service_role";

grant truncate on table "public"."member_active" to "service_role";

grant update on table "public"."member_active" to "service_role";

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

grant delete on table "public"."member_status" to "anon";

grant insert on table "public"."member_status" to "anon";

grant references on table "public"."member_status" to "anon";

grant select on table "public"."member_status" to "anon";

grant trigger on table "public"."member_status" to "anon";

grant truncate on table "public"."member_status" to "anon";

grant update on table "public"."member_status" to "anon";

grant delete on table "public"."member_status" to "authenticated";

grant insert on table "public"."member_status" to "authenticated";

grant references on table "public"."member_status" to "authenticated";

grant select on table "public"."member_status" to "authenticated";

grant trigger on table "public"."member_status" to "authenticated";

grant truncate on table "public"."member_status" to "authenticated";

grant update on table "public"."member_status" to "authenticated";

grant delete on table "public"."member_status" to "service_role";

grant insert on table "public"."member_status" to "service_role";

grant references on table "public"."member_status" to "service_role";

grant select on table "public"."member_status" to "service_role";

grant trigger on table "public"."member_status" to "service_role";

grant truncate on table "public"."member_status" to "service_role";

grant update on table "public"."member_status" to "service_role";

grant delete on table "public"."members" to "anon";

grant insert on table "public"."members" to "anon";

grant references on table "public"."members" to "anon";

grant select on table "public"."members" to "anon";

grant trigger on table "public"."members" to "anon";

grant truncate on table "public"."members" to "anon";

grant update on table "public"."members" to "anon";

grant delete on table "public"."members" to "authenticated";

grant insert on table "public"."members" to "authenticated";

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



  create policy "Gym staff can insert member active"
  on "public"."member_active"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update member active"
  on "public"."member_active"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view member active"
  on "public"."member_active"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_active.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



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



  create policy "Gym staff can insert account status"
  on "public"."member_status"
  as permissive
  for insert
  to authenticated
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Gym staff can update account status"
  on "public"."member_status"
  as permissive
  for update
  to public
using (public.is_gym_admin_or_owner(gym_id))
with check (public.is_gym_admin_or_owner(gym_id));



  create policy "Users and gym staff can view account status"
  on "public"."member_status"
  as permissive
  for select
  to public
using (((EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.member_id = member_status.member_id) AND (members.user_id = auth.uid())))) OR public.is_gym_admin_or_owner(gym_id)));



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


CREATE TRIGGER trg_prevent_user_id_overwrite BEFORE UPDATE OF user_id ON public.members FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_overwrite();


