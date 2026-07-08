# VideoService — Coding Standards

Python/Pydantic package. See `README.md` for what it does. (Formerly
CustomYoutubeService — renamed when the scope expanded beyond YouTube.)

> **Standalone by design.** This service owns the full gym-video lifecycle:
> gym config authoring, the scrape + RAG-enrich + scan **background worker**, and
> a read-only API. Data lives in the **shared Supabase Postgres** (the `video_*`
> tables defined in `../Database/`): the read API and the FastApiBackend query it,
> the worker writes it, and `make sync-gyms` loads the hand-authored gym configs
> (git-tracked YAML `gyms/<id>.yaml`) into SQL. All SQL lives in `.sql` files read
> via `sql_loader` — never inline.
>
> **The read API has been merged into the FastApiBackend** (`../FastApiBackend/src/videos`
> — a re-authored port keyed by the real gym UUID, with a public slug-keyed
> template catalog + a `presets` import that copies a template into a gym's real
> prod tables; see `Business/pivots/2026-06-24-22-videoservice-api-merged-into-backend.md`).
> The **CRM and the public theme browser now call that backend**, not this service.
> This read API (`src/api`, port 8002, `video.combatden.net`) stays live only as
> the source for the member **MobileApp**, which has not been repointed yet — once
> it is, this read API can be retired. The **background worker** (`src/worker`,
> `make worker`) and the gym-config YAML authoring remain owned here regardless.

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
  `src/shared/`). Read-path queries live in `src/api/sql/`; the worker's pipeline
  queries in `src/worker/sql/`; the YAML-sync scripts' in `scripts/sql/`. Use
  `:param` bind params for values; `{var}` only for structural parts (e.g. a WHERE
  clause).

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
The worker stages are covered by `tests/test_worker_*.py` (pure transforms,
funnel, enricher, scanner, the tick, and the resource lock) against
`tests/worker_fakes.py` — no DB or provider key needed.

---

## What NOT to do

- Do not hardcode gym-specific names, disciplines, or search prompts in Python.
  Anything specific to one gym belongs in `gyms/<gym_id>.yaml`.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not add scraping or scanning calls to `src/api/` or `schema/` — the whole
  scrape → funnel → enrich → scan → feed-write pipeline lives in `src/worker/`.
  The read path only *reads* (via `.sql` in `src/api/sql/`). There are two write
  paths: the **worker** writes the pool + RAG + feed + runs + cost log through its
  own `src/worker/sql/`, and `make sync-gyms` / `make import-yaml` load the YAML
  gym configs through `scripts/shared/video_db_writer.py` (`scripts/sql/`).

---

## Jobs / workflow

Two kinds of job. **Gym-config tooling** (author YAML + load it into SQL) runs as
`scripts/` modules + `make` targets; the **content pipeline** runs as the background
worker:

1. **Make/edit a gym** (`make gym-check GYM_ID=<id|all>`) — author/update
   `gyms/<gym_id>.yaml` and validate it round-trips the `Gym` schema (YAML-only).
2. **Sync gyms → SQL** (`make sync-gyms GYM_ID=<id|all>`) — upsert the authored
   gym files into `video_gym` + its query/class/reward child tables, then load
   the existing `videos/` pool + each gym's good/rejected feeds into SQL (pool
   upserts, feeds rewrite per gym — no re-scrape). Fully idempotent. It runs the
   import with `--skip-cost-log`, so the append-only `cost_log.yaml` is **not**
   imported here (re-running would duplicate ledger rows); load it once by hand
   with `poetry run python -m scripts.import_yaml.run` if you need the history.
   These write through `scripts/shared/video_db_writer.py` + `scripts/sql/` and
   pick their DB via the **`ENV_FILE`** flag (default `.env`; `ENV_FILE=.env.prod`
   targets prod) — see `scripts/shared/db_target.py`.
3. **The content worker** (`make worker` → `python -m src.worker.run`) — the
   scrape → funnel → enrich → scan → feed-write pipeline, detailed in the next
   section. It **replaced** the old standalone `scripts/scraper` + `scripts/scan`
   jobs (both deleted, along with `src/classification`); it writes through its own
   `src/worker/sql/`, not `VideoDbWriter`.

---

## The background worker (`src/worker`)

A standalone long-running process — `python -m src.worker.run` (`make worker`) — that
regenerates gym feeds and builds the RAG layer. **Not a web server, no port.** It is the
video half of the combined `deploy/` container (the other half is FastApiBackend's
uvicorn). **There is no job queue and no control surface** — the worker is fully
self-scheduling: each tick derives the single highest-priority "due" gym straight from
timestamps already in the schema (`video_run`, `gym_video_spec`, `gym_video_feed`). The
FastApiBackend never triggers a run; its only involvement is a read-only status endpoint
(`GET …/video-worker/status`) that reads the same run rows the worker writes. The two
never call each other.

### The tick

`run.py` is a loop: one gym per tick, then wait `worker_poll_seconds` (60) for the next.
Each `WorkerService.run_tick`:

1. **Acquires a global TTL lock** `"video_worker_run"` on the shared `resource_locks`
   table (single-shot, non-blocking — a second worker just no-ops the tick). TTL =
   `worker_lock_ttl_seconds` (900s), renewed by a heartbeat every
   `worker_heartbeat_seconds` (300s); a lost heartbeat aborts the run mid-pipeline. So
   only one gym is ever processed at a time across every worker instance.
2. **Recovers orphans** — under the exclusive lock, any `video_run` still `status='running'`
   must be from a dead process: it is marked `failed` (`error='orphaned'`). There is no
   re-enqueue — the run's `created_at` still counts as that gym's last-run watermark, and
   the next tick's derivation step (below) re-selects the gym once it is next due (subject
   to the run caps). This just clears the stuck `running` row so the state stays truthful.
3. **Checks the system-wide run cap** — if runs of ANY status across ALL gyms in the
   rolling `worker_cap_window_hours` (24h) window already reach `worker_system_run_cap`
   (5), the tick skips selection entirely (the global Apify/quota budget guard).
4. **Derives the single due gym** (`worker_select_due_gym.sql`) — see *Scheduling* below.
   Nothing due → the tick ends with no run.

### Scheduling: due-gym derivation + the run caps

No queue, no enqueue call from anywhere — the worker computes its own work every tick
from timestamps already in the schema. A gym (one with a video spec) is **due** when a
trigger is newer than its last run's **start** (`MAX(video_run.created_at)`, ANY status —
a failed run still advances this watermark, so a deterministic failure does not hot-loop;
it waits for a new trigger or the weekly floor). The trigger decides the priority **tier**
(lower tier wins; ties go to the oldest-waiting trigger first):

- **tier 1** — the gym's latest `gym_video_spec` version with `source='admin_update'`
  (an owner/agent edit) is newer than the last run start.
- **tier 2** — the gym's latest MANUAL `gym_video_feed` curation (`curated_at`, any
  reject/keep/re-add) is newer than the last run AND has settled at least
  `worker_curation_batch_hours` (1h) ago — so a burst of curations batches into one run.
- **tier 3** — the gym's last run is at least `worker_weekly_refresh_days` (7) old
  (periodic refresh). A never-run gym qualifies only via tier 1/2 — a preset-only gym
  that was never edited is NOT auto-run (matches the old "preset import does not
  enqueue" behavior).

Two rolling-`worker_cap_window_hours` run caps, both counting runs of ANY status (the
poison-loop guard): **per-gym** — `worker_gym_run_cap` (2), enforced inside the
derivation query itself; **system-wide** — `worker_system_run_cap` (5), checked by the
tick (step 3 above) before the derivation query runs at all. `GET …/video-worker/status`
reads the gym's runs (running / last-run-status / last-completed timestamp) — there is no
`queued` field to report.

### The pipeline (six stages, per gym)

1. **Spec** — load the gym's latest spec from the `gym_video_spec_latest` view; compute
   `criteria_changed` by comparing the current `(videos_desc, avoid_desc)` against the spec
   version in force at the gym's previous **completed** run (drives incremental vs fresh).
2. **Scrape** — one Apify `streamers/youtube-scraper` actor run per spec query (subtitles
   ride inline), concurrency `worker_scrape_concurrency` (4). A failed query is dropped, not
   fatal. Results are **merge-upserted** into the shared `video` pool (`source_queries`
   accumulate; `tag`/`disciplines` never overwritten — fresh scrapes land untagged).
3. **Funnel** — pick candidates up to `scan_budget_per_run` (1000). **Tier 1**: pool rows
   whose `source_queries` overlap the spec queries AND match a gym discipline (or are
   untagged — so this run's fresh scrapes get scanned), relevance-ordered; incremental mode
   excludes the previous run's already-verdicted ids. **Tier 2** (only if room left): every
   spec query embedded in one call, then a cosine top-`rag_probe_top_k` (40) probe over
   discipline-matched `video_rag` rows. A full Tier 1 skips Tier 2 entirely.
4. **Enrich** — for each un-enriched candidate **and** the gym's owner-section videos, ONE
   multimodal LLM call (`enrich_model`, `gemini/gemini-2.5-flash-lite`; thumbnail image +
   metadata + a `enrich_transcript_char_budget` (8000-char) transcript slice) →
   `{genre tag, disciplines, prose summary, facets}`. The tag + disciplines are written back
   onto the `video` pool row; the summary is embedded (batched) and stored as a `video_rag`
   row.
5. **Scan** — batched keep/drop (`scan_batch_size` ≈ 12 summaries per LLM call,
   `scan_model` `gemini/gemini-2.5-flash-lite`) against the spec's `videos_desc`/`avoid_desc`.
   A missing verdict defaults to rejected.
6. **Feed write (carry-forward)** — open a new `video_run` (`running`), copy the previous
   completed run's rows FIRST (ALL rows in incremental mode; only manual-curation rows in a
   fresh run), then insert the fresh automatic verdicts `ON CONFLICT DO NOTHING` — so the
   owner's manual keep/reject always wins. Complete the run (`status='completed'`), which is
   what makes it the served run.

Each stage's spend is logged to the generic **`cost_log`** table (shared across every
cost-bearing system, not just video — see `../Database/CLAUDE.md`) as `search` / `enrich` /
`embed` / `scan` rows, each stamped `source='video'`, `run_id` (the run's id as TEXT, no FK),
`gym_id`, `stage`, `model` (the LLM/embedding model used, NULL for the Apify search stage),
and `cost_usd` (the row's single USD total; `breakdown` still carries the component detail
map). **A failed stage marks the run `failed`** — its `created_at` still counts as the gym's
last-run watermark, so a deterministic failure does not hot-loop; the gym simply waits for a
new tier-1/2 trigger or the tier-3 weekly floor to become due again (poison guard — no manual
re-trigger exists).

### Settings + the embedding contract

Worker knobs live in `src/worker/worker_config.py` (`WorkerSettings`) — the models above,
scheduling (`worker_cap_window_hours` (24), `worker_gym_run_cap` (2),
`worker_system_run_cap` (5), `worker_curation_batch_hours` (1),
`worker_weekly_refresh_days` (7) — see *Scheduling* above), budgets (`scan_budget_per_run`,
`scan_batch_size`, `rag_probe_top_k`, `enrich_transcript_char_budget`), concurrency
(`worker_*_concurrency`), the lock/loop timers, and `apify_token`. It reads `DATABASE_URL`
from `src/api/config.py` and the LLM provider keys (`gemini_api_key`, `openai_api_key`,
`anthropic_api_key`) from `src/core/config.py` — three `Settings` classes over the one
`.env`.

The **embedding contract is cross-service.** The worker embeds with
`embedding_model` (`openai/text-embedding-3-small`) into `video_rag.embedding` typed
`vector(1536)`; `run.py` asserts `embedding_dim == 1536` at startup. The FastApiBackend RAG
readers (member recs + semantic search) rank against those same `video_rag` embeddings, so
both sides pin the **same model + `vector(1536)` dimension** (`settings.video_embedding_dim`
on the backend). Changing one without the other silently breaks similarity.

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
  `.env`; `ENV_FILE=.env.prod` → prod). Prod helper: `make sync-gyms-prod
  GYM_ID=all` (sync + pool/feed import against prod). Keep prod secrets in `.env.prod`
  (gitignored). **Never `supabase db pull` while local schema is ahead of prod** —
  it generates destructive migrations that drop the new tables.
- This `Dockerfile` containerizes only the **read API**. The **background worker**
  (`src/worker`) ships separately, in the combined `../deploy/` image (FastApiBackend
  uvicorn + this worker on an always-on platform — see `../deploy/CLAUDE.md` and
  `../DEPLOYMENT.md`). The gym-config `sync-gyms` / `import-yaml` scripts stay local.
