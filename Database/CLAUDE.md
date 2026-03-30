# Supabase Project

## Schema workflow
- **Never edit migration files directly.** Only modify schema files in `schemas/`.
- The user will run the Supabase migration command themselves.

## Security
- Always enable Row Level Security (RLS) on every table.
- Always use `REVOKE UPDATE` on immutable columns (e.g. PKs, FKs, created_at) for the `authenticated` role.

## Integrity constraints
- Always name constraints with the `CONSTRAINT` keyword for readable error messages (e.g. `CONSTRAINT membership_must_match_gym`).
- Prefer composite foreign keys over triggers for cross-table validation (e.g. ensuring crm_user_id belongs to the correct gym_id).
- Only use triggers when the constraint can't be expressed as a FK (e.g. JSONB array validation, immutability logic).
- Keep triggers in the same schema file as the table they apply to, not in a separate file.

## Structure
- `schemas/` — source-of-truth SQL for each table (DDL, RLS policies, column permissions, triggers)
- `migrations/` — generated migration files (do not touch)
- `config.toml` — Supabase project config
