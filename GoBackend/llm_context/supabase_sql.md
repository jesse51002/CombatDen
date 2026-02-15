# Supabase SQL Patterns and Security

This document contains detailed patterns for working with Supabase PostgreSQL, including Row Level Security (RLS), column-level permissions, and database triggers.

## Row Level Security (RLS)

**ALWAYS enable RLS** on tables containing user data to ensure users can only access their own data.

### IMPORTANT: Policy Planning Workflow

**BEFORE creating any RLS policies (SELECT, UPDATE, INSERT), ALWAYS ask the user for clarification:**

1. **Who can SELECT (read) from this table?**
   - Only the data owner (e.g., user can view own data)?
   - Data owner AND related parties (e.g., gym owner can view member data)?
   - Read-only for everyone with access?

2. **Who can UPDATE (modify) in this table?**
   - Data owner only?
   - Data owner AND related parties (e.g., gym owner can update member profiles)?
   - No one (immutable/read-only table)?

3. **Who can INSERT (create) in this table?**
   - No one (backend only - most common)?
   - Users with validation (e.g., activity logs with membership check)?
   - Special cases only?

4. **Who can DELETE from this table?**
   - **NEVER allow DELETE for authenticated users**
   - Always backend/service role only

**Example clarification questions:**
- "For the `user_activities` table, who should be able to view activities? Just the user, or gym owners too?"
- "Should users be able to update their own activities, or is this an immutable log?"
- "Can users insert their own activities, or should this be backend-only?"

**Do not make assumptions** - different tables have different access patterns. Always clarify before writing policies.

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

## Restricting INSERT and DELETE Operations

**CRITICAL: NEVER allow DELETE operations for authenticated users. EVER.**

**IMPORTANT: By default, NEVER allow INSERT operations for authenticated users.**

Only the service role (backend) should have INSERT and DELETE permissions. Regular users should only have SELECT and UPDATE access through RLS policies (and INSERT only in rare, validated exceptions).

### Why Restrict INSERT/DELETE

- **DELETE (NEVER ALLOW)**:
  - Use soft deletes or backend-controlled hard deletes to maintain data integrity
  - Prevents permanent data loss from user actions
  - Maintains audit trails and data history
  - Allows data recovery if needed
  - **NO EXCEPTIONS** - DELETE is always backend-only

- **INSERT (RARELY ALLOW)**:
  - Backend should control row creation to enforce business logic
  - Backend generates IDs and sets immutable fields correctly
  - Backend can validate, transform, and enrich data before insertion
  - Backend logs all creation events
  - Only allow INSERT for users in special cases with strict validation (e.g., activity logs)

- **Security**: Prevents users from creating malicious data or permanently deleting records
- **Data Integrity**: Backend enforces consistency and business rules
- **Audit**: Complete logging of all data changes

### Default: No INSERT or DELETE Policies

```sql
-- Enable Row Level Security
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

-- ONLY create SELECT and UPDATE policies
-- DO NOT create INSERT or DELETE policies for authenticated users

-- Policy: Users can view their own data
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

-- NO INSERT POLICY = authenticated users cannot insert
-- NO DELETE POLICY = authenticated users cannot delete
```

### Backend Service Role

Your Go backend should use the Supabase **service role key** for INSERT and DELETE operations:

```go
// Use service role client for INSERT/DELETE operations
serviceClient := supabase.CreateClient(
    supabaseURL,
    supabaseServiceKey,  // Service role key, not anon key
)

// Backend can insert rows
func (s *GymService) CreateGym(ctx context.Context, req *CreateGymRequest) error {
    // Service role bypasses RLS, can insert directly
    _, err := s.serviceClient.From("gyms").Insert(gymData).Execute()
    return err
}

// Backend can delete rows
func (s *GymService) DeleteGym(ctx context.Context, gymID string) error {
    // Service role bypasses RLS, can delete directly
    _, err := s.serviceClient.From("gyms").Delete().Eq("gym_id", gymID).Execute()
    return err
}
```

### Soft Delete Pattern (Recommended)

Instead of hard deletes, use soft deletes with a deleted_at timestamp:

```sql
-- Add deleted_at column to table
ALTER TABLE gyms ADD COLUMN deleted_at TIMESTAMPTZ DEFAULT NULL;

-- Update SELECT policy to exclude soft-deleted rows
CREATE POLICY "Users can view own active data"
    ON gyms
    FOR SELECT
    USING (auth.uid() = owner_id AND deleted_at IS NULL);

-- Backend marks rows as deleted instead of removing them
-- UPDATE gyms SET deleted_at = NOW() WHERE gym_id = $1;
```

### RLS Policy Summary

**Before creating policies, ASK the user about access requirements!**

**Default policy approach:**
- ✅ SELECT (with RLS filtering - ask who can read)
- ⚠️ UPDATE (ask if data is mutable and who can modify)
- ⚠️ INSERT (ask if needed - default is backend-only)
- ❌ DELETE (**NEVER** - always backend/service role only)

**REMEMBER:** Always clarify with the user before assuming access patterns!

### Exception: Admin Users

If you need admin users with full access, create a separate admin role or check user metadata:

```sql
-- Policy: Admins can insert (example - use sparingly)
CREATE POLICY "Admins can insert data"
    ON gyms
    FOR INSERT
    WITH CHECK (
        (auth.jwt() ->> 'role')::text = 'admin'
    );

-- Policy: Admins can delete (example - use sparingly)
CREATE POLICY "Admins can delete data"
    ON gyms
    FOR DELETE
    USING (
        (auth.jwt() ->> 'role')::text = 'admin'
    );
```

**Note**: Admin policies should be used sparingly. Most applications should handle all INSERT/DELETE operations through the backend service layer.

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

## Timestamp Patterns

**Use `DEFAULT now()` for automatic timestamps to ensure data consistency and prevent API mistakes.**

### Common Timestamp Columns

```sql
CREATE TABLE example (
    id UUID NOT NULL DEFAULT uuid_generate_v4(),

    -- Auto-generated timestamps (always use DEFAULT)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    time TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- User-controlled timestamps (no default)
    last_login TIMESTAMPTZ,
    last_class TIMESTAMPTZ,
    scheduled_date TIMESTAMPTZ,
    PRIMARY KEY (id)
);
```

### When to Use DEFAULT for Timestamps

**Use `DEFAULT now()`:**
- ✅ `created_at` - Record creation time
- ✅ `time` - Activity/transaction timestamp
- ✅ Any timestamp that should be "right now" when the record is created
- ✅ Audit timestamps that must be database-controlled

**Benefits:**
- Prevents API from sending incorrect timestamps
- Ensures consistency across all records
- Database-enforced, no application logic needed
- Cannot be manipulated by users or buggy code

**No default (user-controlled timestamps):**
- ❌ `last_login` - Set when user actually logs in
- ❌ `last_class` - Set when user attends class
- ❌ `scheduled_date` - Future date set by user
- ❌ Any timestamp that represents a specific past or future time

### Note on `updated_at`

For `updated_at` columns that change on every update, use a database trigger instead of GENERATED ALWAYS:

```sql
-- Create update trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to table
CREATE TRIGGER update_gyms_updated_at
    BEFORE UPDATE ON gyms
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

---

## Composite Foreign Key Constraints

**ALWAYS add composite foreign key constraints when a table has both `user_id` and `gym_id` columns.**

This ensures referential integrity - users can only create records for gyms they are members of.

### Pattern: User-Gym Foreign Key

```sql
CREATE TABLE user_activities (
    activity_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    gym_id UUID NOT NULL REFERENCES gyms(gym_id),
    activity_type VARCHAR,
    activity_info JSONB,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (activity_id),
    -- Composite foreign key constraint
    CONSTRAINT user_gym
        FOREIGN KEY (user_id, gym_id)
        REFERENCES user_gym_profiles (user_id, gym_id)
);
```

### Why Use Composite Foreign Keys

- **Enforces gym membership**: Users can't create records for gyms they're not members of
- **Database-level validation**: Prevents invalid data even if application logic fails
- **Referential integrity**: If a user is removed from a gym, related records can be handled with CASCADE
- **Complements RLS policies**: Works alongside INSERT policies that check gym membership

### When to Use

Add this constraint to ANY table that has both:
1. `user_id` column (references auth.users)
2. `gym_id` column (references gyms)

**Examples of tables that need this constraint:**
- `user_activities` - User activities at a gym
- `user_gym_transactions` - Transactions between user and gym
- Any table linking users to gyms for actions/data

**Tables that DON'T need this constraint:**
- `user_gym_profiles` - This IS the membership table (has the composite PK)
- `gyms` - Only has gym_id, no user_id
- `gym_history` - Only has gym_id, no user_id

### Constraint Naming Convention

Always use `user_gym` as the constraint name for consistency:

```sql
CONSTRAINT user_gym
    FOREIGN KEY (user_id, gym_id)
    REFERENCES user_gym_profiles (user_id, gym_id)
```

### Combined with RLS INSERT Policy

The composite foreign key works together with RLS INSERT policies:

```sql
-- RLS policy checks gym membership at policy level
CREATE POLICY "Users can insert activities for their gyms"
    ON user_activities
    FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.user_id = auth.uid()
            AND user_gym_profiles.gym_id = user_activities.gym_id
        )
    );

-- Foreign key constraint enforces it at database level
-- Both provide defense in depth
```

---

## UUID Primary Keys

Use UUIDs instead of sequential integers for better security and distributed system support.

### UUID Setup

```sql
-- Enable UUID extension (in initial migration)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Table with UUID Primary Key and Timestamps

```sql
CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    gym_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (gym_id)
);
```

**Use `DEFAULT` for:**
- UUID primary keys - auto-generates on INSERT, prevents users from specifying their own IDs
- Timestamps - ensures database-controlled time, prevents API mistakes
- Any value that should be auto-generated at INSERT time

**Benefits:**
- Data consistency - timestamps always accurate
- Prevents API errors - can't send wrong timestamp values
- Database-enforced - no application logic needed

**Important:** Use `DEFAULT`, NOT `GENERATED ALWAYS AS` - functions like `uuid_generate_v4()` and `now()` are volatile (non-immutable) and cannot be used with `GENERATED ALWAYS AS`. Use `GENERATED ALWAYS AS` only for computed columns based on OTHER columns in the same row.

### UUID Best Practices

- **Benefits of UUIDs**:
  - No sequential ID exposure (security)
  - Easier distributed systems (no ID conflicts)
  - Can generate IDs client-side if needed
  - Better for multi-tenant systems
- **Foreign keys**: Use `UUID` type and `REFERENCES` clause
- **Always reference `auth.users(id)`** for user ownership - Supabase auth.users uses UUID
- **Performance**: UUIDs are larger than integers but performance impact is minimal with proper indexing
- **ALWAYS use `DEFAULT uuid_generate_v4()`** - NOT `GENERATED ALWAYS AS` (uuid_generate_v4 is volatile)

---

## Complete Example

Here's a complete example combining all patterns (based on gyms.sql):

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create table with UUID primary key and timestamps
CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    gym_name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (gym_id)
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

-- NO INSERT POLICY: Only backend/service role can insert
-- NO DELETE POLICY: Only backend/service role can delete

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

1. **Making assumptions about access patterns**: ALWAYS ask the user who can SELECT/UPDATE/INSERT before creating policies
2. **Forgetting composite foreign key constraints**: Tables with both user_id and gym_id MUST have the user_gym constraint
3. **Forgetting to enable RLS**: Tables without RLS are fully accessible regardless of policies
4. **Allowing DELETE for authenticated users**: NEVER EVER create DELETE policies for regular users
5. **Allowing INSERT without asking**: Default should be backend-only; only allow INSERT after user confirms and with strict validation
6. **Missing WITH CHECK on UPDATE**: Without WITH CHECK, users might update rows to values that violate policies
7. **Not revoking column permissions**: Even with RLS, immutable columns can be changed without explicit REVOKE
8. **Trigger errors silently fail**: Always test triggers and check logs
9. **SECURITY DEFINER risks**: Be careful with trigger functions - they run with elevated privileges
10. **Not testing with different user contexts**: Always test RLS with multiple user IDs
11. **Using anon key instead of service key**: Backend INSERT/DELETE operations must use service role key
12. **Trailing commas in table definitions**: Watch for syntax errors in column definitions
