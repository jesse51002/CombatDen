# Supabase SQL Patterns and Security

This document contains detailed patterns for working with Supabase PostgreSQL, including Row Level Security (RLS), column-level permissions, and database triggers.

## Row Level Security (RLS)

**ALWAYS enable RLS** on tables containing user data to ensure users can only access their own data.

### Basic RLS Setup

```sql
-- Enable Row Level Security on table
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;
```

### RLS Policies

Create separate policies for SELECT (read) and UPDATE (modify) operations.

**SELECT Policy - Reading Data**
```sql
-- Policy: Users can read their own data
CREATE POLICY "Users can view own data"
    ON gyms
    FOR SELECT
    USING (auth.uid() = owner_id);
```

**UPDATE Policy - Modifying Data**
```sql
-- Policy: Users can update their own data
CREATE POLICY "Users can update own data"
    ON gyms
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);
```

### Policy Components

- **`USING` clause**: Determines which existing rows are visible/modifiable. Acts as a filter on SELECT and UPDATE operations.
- **`WITH CHECK` clause**: Validates the updated row values. Ensures users can't update a row to violate the policy.
- **`auth.uid()`**: Supabase function that returns the authenticated user's ID from the JWT token.

### Best Practices for RLS

- **Always test policies thoroughly** - Incorrect RLS can expose data or block legitimate access
- **Use descriptive policy names** - Makes debugging and maintenance easier
- **Start restrictive, then open up** - Begin with strict policies and relax as needed
- **Test with different user contexts** - Verify policies work for different user roles
- **Document policy intent** - Add comments explaining why each policy exists
- **USING clause on UPDATE** - Determines which rows the user can update
- **WITH CHECK clause on UPDATE** - Ensures the updated values satisfy the policy

---

## Column-Level Permissions

Prevent modification of immutable columns (IDs, ownership fields, creation timestamps) even if a user has UPDATE access to the row.

### Revoking UPDATE on Immutable Columns

```sql
-- Prevent updates to immutable columns for authenticated users
REVOKE UPDATE (owner_id, gym_id) ON TABLE gyms FROM authenticated;
```

### Common Immutable Columns

- **Primary keys**: `id`, `gym_id`, `user_id`, etc.
- **Foreign keys for ownership**: `owner_id`, `created_by`, etc.
- **Timestamps**: `created_at` (updated_at can be mutable)
- **Audit fields**: Any field used for auditing or tracking

### Column-Level Security Best Practices

- **Column-level permissions complement RLS** - RLS controls row access, column permissions control field mutability
- **Document why columns are immutable** - Add comments in migration files
- **Apply early in table lifecycle** - Set permissions when creating the table
- **Revoke from appropriate roles**:
  - `authenticated` - For logged-in users
  - `anon` - For anonymous access (if applicable)

---

## Database Triggers for Automatic Row Creation

Use triggers to automatically create related records when certain events occur, such as creating a user profile when a new user signs up.

### Trigger Function Pattern

```sql
-- Trigger function to create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Insert a new row in the related table
  INSERT INTO public.users (id)
  VALUES (NEW.id);

  -- Return NEW for AFTER INSERT triggers
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Creating the Trigger

```sql
-- Trigger that fires when new user signs up
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
```

### Trigger Function Requirements

- **Must be `SECURITY DEFINER`** - Executes with privileges of the function owner, not caller
  - Required because trigger runs in context of auth.users (system table)
  - Allows inserting into public schema tables that caller might not have direct access to
- **Must return `NEW`** - For AFTER INSERT triggers, return the new row
- **Use `LANGUAGE plpgsql`** - PostgreSQL procedural language
- **Should be in `public` schema** - For application-level logic

### Common Trigger Use Cases

- **Creating default user profiles** - When new user signs up
- **Creating default settings/preferences** - Initialize user configuration
- **Creating related records** - Set up necessary child records
- **Initializing default data** - Create starter content for new users

### Trigger Best Practices

- **Keep trigger functions simple and focused** - One clear purpose per trigger
- **Handle errors gracefully** - Failed trigger rolls back the entire transaction
- **Use triggers for cross-table consistency** - Not business logic (put that in service layer)
- **Document trigger behavior** - Add detailed comments in migration files
- **Test triggers thoroughly** - They run automatically and can cause unexpected behavior
- **Consider idempotency** - What happens if trigger runs twice?
- **Use `AFTER INSERT ON auth.users`** - Standard pattern for user signup triggers

---

## UUID Primary Keys

Use UUIDs instead of sequential integers for better security and distributed system support.

### UUID Setup

```sql
-- Enable UUID extension (in initial migration)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Table with UUID Primary Key (Generated Always)

```sql
CREATE TABLE gyms (
    gym_id UUID PRIMARY KEY GENERATED ALWAYS AS (uuid_generate_v4()) STORED,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    gym_name VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Alternative: DEFAULT Syntax

```sql
CREATE TABLE gyms (
    gym_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    gym_name VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### UUID Best Practices

- **Benefits of UUIDs**:
  - No sequential ID exposure (security)
  - Easier distributed systems (no ID conflicts)
  - Can generate IDs client-side if needed
  - Better for multi-tenant systems
- **Foreign keys**: Use `UUID` type and `REFERENCES` clause
- **Always reference `auth.users(id)`** for user ownership - Supabase auth.users uses UUID
- **Performance**: UUIDs are larger than integers but performance impact is minimal with proper indexing
- **Use `GENERATED ALWAYS AS` or `DEFAULT`** - Both work, choose based on preference

---

## Complete Example

Here's a complete example combining all patterns (based on gyms.sql):

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create table with UUID primary key
CREATE TABLE gyms (
    gym_id UUID PRIMARY KEY GENERATED ALWAYS AS (uuid_generate_v4()) STORED,
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    gym_name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view their own data
CREATE POLICY "Users can view own data"
    ON gyms
    FOR SELECT
    USING (auth.uid() = owner_id);

-- RLS Policy: Users can update their own data
CREATE POLICY "Users can update own data"
    ON gyms
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (owner_id, gym_id) ON TABLE gyms FROM authenticated;

-- Trigger function to automatically create a user record on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id)
  VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute function on new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
```

---

## Testing RLS Policies

### Using Supabase SQL Editor

```sql
-- Test as specific user (set role and JWT claims)
SET request.jwt.claims.sub = 'user-uuid-here';

-- Run queries to test
SELECT * FROM gyms; -- Should only see user's gyms
UPDATE gyms SET gym_name = 'New Name' WHERE gym_id = 'gym-uuid'; -- Should only work for user's gyms
```

### Using Application Tests

Always write integration tests that verify:
- Users can only view their own data
- Users can only update their own data
- Users cannot view or update other users' data
- Column-level permissions prevent unwanted updates to immutable fields

---

## Common Pitfalls

1. **Forgetting to enable RLS**: Tables without RLS are fully accessible regardless of policies
2. **Missing WITH CHECK on UPDATE**: Without WITH CHECK, users might update rows to values that violate policies
3. **Not revoking column permissions**: Even with RLS, immutable columns can be changed without explicit REVOKE
4. **Trigger errors silently fail**: Always test triggers and check logs
5. **SECURITY DEFINER risks**: Be careful with trigger functions - they run with elevated privileges
6. **Not testing with different user contexts**: Always test RLS with multiple user IDs
7. **Trailing commas in table definitions**: Watch for syntax errors in column definitions
