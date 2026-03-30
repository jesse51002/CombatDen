alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

alter table "public"."gyms" alter column "estimated_classes_rank_1" set default 20;

alter table "public"."gyms" alter column "estimated_classes_rank_2" set default 100;

alter table "public"."gyms" alter column "estimated_classes_rank_3" set default 200;

alter table "public"."gyms" alter column "estimated_classes_rank_4" set default 200;

alter table "public"."gyms" alter column "estimated_classes_rank_5" set default 200;

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";


