# VideoService — Coding Standards

Python/Pydantic package. See `README.md` for what it does. (Formerly
CustomYoutubeService — renamed when the scope expanded beyond YouTube.)

> **Standalone by design.** This service owns the full gym-video lifecycle:
> gym config authoring, video pool scraping + classification, feed scanning, and
> a read-only API consumed by other systems. Data lives in the **shared Supabase
> Postgres** (the `video_*` tables defined in `../Database/`): the read API
> queries it, and the pipeline scripts write it. The hand-authored gym configs
> stay git-tracked YAML (`gyms/<id>.yaml`) and are loaded into SQL by
> `make sync-gyms`. The Pydantic schema may still eventually fold into
> `../FastApiBackend/`; keep the surface small. All SQL lives in `.sql` files
> read via `sql_loader` — never inline.

---

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the
user's explicit response. Never assume, recommend-and-proceed, or defer the
choice unilaterally. Presenting researched options is encouraged; making the
choice for the user is not.

---

## Skills are living documents

When you're working through a skill (or any reference doc / `SKILL.md` it loads)
and realize its guidance is wrong, outdated, or actively holding the work back —
a recommended source that returns bad results, a step that no longer fits, a
better tool you've found — do **not** silently work around it:

1. Use the better approach for the task in front of you.
2. **Recommend the specific skill fix to the user and wait for approval** (per
   *No assumptions* — present it, don't self-apply).
3. On approval, **update the skill file** so the lesson is baked in next time.

Skills are ever-evolving: every real-world correction should feed back into them.

---

## CLAUDE.md is a living document

This file is a living document — exactly like a skill (above), it must track reality. Whenever the service genuinely diverges from what this CLAUDE.md says (a renamed system, a changed config layout, a new endpoint, a rule the code has outgrown on purpose, an architecture change), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

---

## Core principle: gym-agnostic

Nothing gym-specific lives in Python code. Each gym's hand-authored config (its
disciplines / `gym_type`, chosen ThemeService design id, video specification,
search queries, and optional classes + rewards) lives in `gyms/<gym_id>.yaml` —
the git-tracked source of truth — and is synced into SQL with `make sync-gyms`.
The machine-generated state (the shared video pool, each gym's curated
good/rejected feed, and the spend ledger) lives in the `video_*` tables in
Postgres. Adding a new gym is still a YAML change (author the file, then sync).

If you find yourself adding a constant, enum value, or class branch that only
makes sense for one gym, push back — it belongs in YAML. The one exception is
the `VideoType` enum: it is the fixed, shared genre vocabulary every gym draws
from, not a per-gym value.

---

## Sibling repos

- `../Database/` — owns the Postgres schema. The `video_*` tables live in
  `Database/supabase/schemas/`, RLS in `access_rules/`, enums mirrored in
  `python_data/schema/`. **You never run migrations** — the user does (see
  Database's CLAUDE.md). Edit schema files there, not migration files.
- `../FastApiBackend/` — its `CLAUDE.md` carries the broader Python conventions
  for this monorepo (imports, enums, type hints, async, error handling). Apply
  those here unless this file overrides. Its `DirectDatabasePool` + `sql_loader`
  are the patterns this service copies (`src/shared/`).
- `../ThemeService/` — modelled on its read-only `src/api`. Each gym's YAML
  stores its chosen ThemeService design id.

---

## Python standards

- **Pydantic v2.** Every model sets `ConfigDict(extra="forbid")` so YAML typos
  fail loudly.
- **One concept per file.** Each Pydantic class lives in its own file under
  `schema/` unless several classes form one tight unit (e.g. `VideoSearch` +
  `VideosConfig`).
- **Native generics** (`list[X]`, `dict[str, Y]`), pipe unions (`X | None`),
  type hints on every parameter and return.
- **Absolute imports** from `schema.*` / `src.*` / `scripts.*`. No relative imports.
- **Constants in `UPPER_CASE`** at the top of the file. No magic strings or
  regexes mid-function.

---

## No inline prompts or SQL

- **Never inline an LLM/agent prompt in Python.** Every prompt lives in its own
  `.md` file and is read at use. Python may hold the *path* constant, never the
  prompt text.
- **Never inline SQL in code.** Every query lives in its own `.sql` file and is
  read at use via `sql_loader.load_sql` (copied from `../FastApiBackend/` into
  `src/shared/`). Read-path queries live in `src/api/sql/`; write-path queries in
  `scripts/sql/`. Use `:param` bind params for values; `{var}` only for
  structural parts (e.g. a WHERE clause).

---

## Async everywhere

Every service method is `async`, matching the monorepo's FastAPI convention. The
read path does real async I/O against Postgres via SQLAlchemy + asyncpg — see
`src/shared/database.py` (`DirectDatabasePool`, copied from `../FastApiBackend/`).
Do not introduce blocking I/O on a hot path. JSONB columns are read tolerantly
(`_as_list` handles the driver returning either a decoded list or a JSON string).

---

## Dependencies

Poetry, with an in-project `.venv` (`poetry.toml`: `in-project = true`). Add
dependencies with `poetry add <pkg>` (dev: `poetry add --group dev <pkg>`) —
never hand-edit `pyproject.toml` or `poetry.lock`. Run all code, scripts, and
tests via **`poetry run`** (`poetry run uvicorn ...`, `poetry run pytest`),
never a bare `python3` or the raw `.venv/bin/*` entrypoints.

---

## Tests

Run the suite with `make test`. Two tiers:

- **Fast unit tests** — no DB. Router/transform logic runs against the in-memory
  `tests/fakes.py` `FakeVideosService`, plus the pure-logic tests (big_group,
  parent_gym_type, avatar_fallback, models, …).
- **DB-integration tests** (`tests/test_integration_db.py`) — exercise the real
  `.sql` against a live Postgres. They **skip automatically unless `DATABASE_URL`
  is set**, so `make test` stays green on a machine without a DB.

Round-trip every gym file with `make gym-check GYM_ID=all` before committing.
(The scrape/scan tests are skipped pending their SQL-writer migration.)

---

## What NOT to do

- Do not hardcode gym-specific names, disciplines, or search prompts in Python.
  Anything specific to one gym belongs in `gyms/<gym_id>.yaml`.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not add scraping or scoring calls to `src/api/` or `schema/` — fetching
  lives in `scripts/scraper/`, scanning in `scripts/scan/`. The read path only
  *reads* (via `.sql` in `src/api/sql/`); every write goes through the pipeline
  scripts' `VideoDbWriter` (`scripts/shared/video_db_writer.py`).

---

## Jobs / workflow

Data lives in Postgres; the gym configs are authored as YAML and synced in. Each
job is a `scripts/` module + `make` target:

1. **Make/edit a gym** (`make gym-check GYM_ID=<id|all>`) — author/update
   `gyms/<gym_id>.yaml` and validate it round-trips the `Gym` schema (YAML-only).
2. **Sync gyms → SQL** (`make sync-gyms GYM_ID=<id|all>`) — upsert the authored
   gym files into `video_gym` + its query/class/reward child tables. Idempotent;
   never touches the curated feed.
3. **Cutover import** (`make import-yaml`) — one-time: load the existing
   `videos/` pool + each gym's good/rejected feeds + `cost_log.yaml` into SQL
   (no re-scrape). Re-runnable; `--skip-cost-log` avoids duplicate ledger rows.
4. **Scrape + classify** (`make scrape`) and **Scan** (`make scan`) — fetch +
   tag the pool, and run the per-gym keep/drop scan. ⚠️ **Not yet migrated to
   SQL**: these still target the removed YAML write methods and are pending the
   scrape/scan → SQL rewrite; their tests are skipped until then.

Every write goes through `scripts/shared/video_db_writer.py` + `scripts/sql/`
(no inline SQL). The write scripts pick their DB via the **`ENV_FILE`** flag
(default `.env`; `ENV_FILE=.env.prod` targets prod) — see `scripts/shared/db_target.py`.

---

## Read-only API (`src/api/`)

Gym-id-keyed, read-only, querying the `video_*` tables. Run with `make api`
(port 8002); requires `DATABASE_URL` in `.env`.

- `GET /gyms` — a paginated page of the gym browser (`GymsPage`); `?query` /
  `?limit` / `?offset`.
- `GET /gyms/{gym_id}` — full `GymDetail` (spec, classes, rewards). The mobile
  app loads this once on selection.
- `GET /gyms/{gym_id}/videos` — paginated curated feed, served in
  `relevance_index` order. `?video_type` / `?big_group` filter (mutually
  exclusive → 400); `?rejected=true` serves the rejected list.
- `GET /gyms/{gym_id}/videos/preview` — one-shot "All" preview (a few videos
  per genre). `?rejected=true` previews the rejected list.
- **Channel-avatar backfill (both feed endpoints).** The pool has no channel
  avatars (Apify never returned them), so every `channel_avatar_url` is empty. At
  serve time an empty avatar is filled with one of the gym's own instructor
  headshots (`gym.classes[].instructor_image_url`), picked deterministically per
  video (so it never flickers / stays cacheable). A real avatar, or a gym with no
  classes, is left untouched. Pure read-path transform. See
  `src/api/service/avatar_fallback.py`.
- `/viewer` — internal dev-only HTML viewer (`viewer_router.py`); never expose
  publicly. ⚠️ Still bundled in the App Runner image, so it's reachable at
  `https://video.combatden.net/viewer` (read-only, but serves the rejected list);
  gating it for prod is a pending decision — see `../DEPLOYMENT.md`.

---

## Production deployment (read-only API)

The read-only API (`src/api/main.py`, `make api`, port 8002) ships to **AWS App
Runner** as a Docker image at `https://video.combatden.net`. See `../DEPLOYMENT.md`
for the full runbook (ARNs, DNS, redeploy, pause/resume).

- The `Dockerfile` builds a small `python:3.13-slim` image with **only `src/` +
  `schema/`** — no baked data (the pool lives in Postgres now). It **requires
  `DATABASE_URL`** at runtime (App Runner service env); a raw `postgresql://`
  Supabase URL is accepted (normalised to asyncpg by `src/shared/database.py`).
- `make docker-build` / `make ecr-push` build + push + trigger a redeploy;
  `make pause` / `make resume` stop / start the deployed App Runner service
  (a cost toggle for the live instance).
- The pipeline scripts stay local and pick their DB via **`ENV_FILE`** (default
  `.env`; `ENV_FILE=.env.prod` → prod). Prod helpers: `make sync-gyms-prod
  GYM_ID=all`, `make import-yaml-prod`. Keep prod secrets in `.env.prod`
  (gitignored). **Never `supabase db pull` while local schema is ahead of prod** —
  it generates destructive migrations that drop the new tables.
- Only the **read path** is containerized; scrape / scan / sync / import stay local.
