# Supabase Project

## Schema workflow
- **Never edit migration files directly.** Only modify schema files in `schemas/`.
- The user will run the Supabase migration command themselves.
- **Never run the migration script** (`supabase db reset`, `supabase migration`, etc.) — the user always runs migrations manually because they need to reset the data. **Do not execute these commands under any circumstances.**
- **Never run the seeding script** (`python python_data/main.py`, etc.) — the user will seed data manually. **Do not execute these commands under any circumstances.**

## Security
- Always enable Row Level Security (RLS) on every table.
- Always use `REVOKE UPDATE` on immutable columns (e.g. PKs, FKs, created_at) for the `authenticated` role.
- Tables with any `stripe_*_id` column must NOT have INSERT or UPDATE RLS policies for the `authenticated` role — those operations go through `service_role` only. SELECT policies for `authenticated` are allowed.

## Integrity constraints
- Always name constraints with the `CONSTRAINT` keyword for readable error messages (e.g. `CONSTRAINT membership_must_match_gym`).
- Always add both an inline foreign key on the column definition AND a composite foreign key at the table level when cross-table gym validation is needed (e.g. `class_id UUID NOT NULL CONSTRAINT fk_schedule_class_id REFERENCES gym_classes(class_id)` inline, plus `CONSTRAINT fk_schedule_class FOREIGN KEY (class_id, gym_id) REFERENCES gym_classes (class_id, gym_id)` at the bottom).
- Prefer composite foreign keys over triggers for cross-table validation (e.g. ensuring crm_user_id belongs to the correct gym_id).
- Only use triggers when the constraint can't be expressed as a FK (e.g. JSONB array validation, immutability logic).
- Keep triggers in the same schema file as the table they apply to, not in a separate file.

## Structure
- `schemas/` — source-of-truth SQL for each table (DDL, RLS policies, column permissions, triggers)
- `migrations/` — generated migration files (do not touch)
- `schema_db_diagram.io` — dbdiagram.io markup; always update this file when adding, removing, or renaming columns/tables
- `config.toml` — Supabase project config
