create table "gyms" (
    gym_id uuid primary key generated always as (uuid_generate_v4()) stored,
    owner_id not null references auth.users(id),
    gym_name varchar,
);

-- Enable Row Level Security
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own data
CREATE POLICY "Users can view own data"
    ON gyms
    FOR SELECT
    USING (auth.uid() = owner_id);

-- Policy: Users can update their own data
CREATE POLICY "Users can update own data"
    ON gyms
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (owner_id, gym_id) ON TABLE gyms FROM authenticated;

-- Trigger to automatically create a public.gyms row when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id)
  VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
