alter table "public"."users" alter column "created_at" set not null;

alter table "public"."users" enable row level security;


  create policy "Users can update own data"
  on "public"."users"
  as permissive
  for update
  to public
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "Users can view own data"
  on "public"."users"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



