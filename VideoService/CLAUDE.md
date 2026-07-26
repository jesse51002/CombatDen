# VideoService — Coding Standards

Python/Pydantic package. See `README.md` for what it does. (Formerly
CustomYoutubeService — renamed when the scope expanded beyond YouTube.)

> **Standalone by design.** This service owns the full gym-video lifecycle: gym
> config authoring and the scrape + RAG-enrich + scan **background worker**. Data
> lives in the **shared Supabase Postgres** (the `video_*` tables defined in
> `../Database/`): the FastApiBackend queries it, the worker writes it, and
> `make sync-gyms` loads the hand-authored gym configs (git-tracked YAML
> `gyms/<id>.yaml`) into SQL. All SQL lives in `.sql` files read via `sql_loader`
> — never inline.
>
> **The read API has been merged into the FastApiBackend** (`../FastApiBackend/src/videos`
> — a re-authored port keyed by the real gym UUID, with a public slug-keyed
> template catalog + a `presets` import that copies a template into a gym's real
> prod tables; see `Business/pivots/2026-06-24-22-videoservice-api-merged-into-backend.md`).
> The **CRM and the public theme browser call that backend**, not this service. The
> **background worker** (`src/worker`, `make worker`) and the gym-config YAML
> authoring are owned here.

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
- `../ThemeService/` — each gym's YAML stores its chosen ThemeService design id.

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
  `src/shared/`). The worker's pipeline queries live in `src/worker/sql/`; the
  YAML-sync scripts' in `scripts/sql/`. Use `:param` bind params for values;
  `{var}` only for structural parts (e.g. a WHERE clause).

---

## Async everywhere

Every service method is `async`, matching the monorepo's FastAPI convention. The
worker does real async I/O against Postgres via SQLAlchemy + asyncpg — see
`src/shared/database.py` (`DirectDatabasePool`, copied from `../FastApiBackend/`).
Do not introduce blocking I/O on a hot path. JSONB columns are read tolerantly
(`src/shared/util/jsonb.py`'s `as_list` handles the driver returning either a
decoded list or a JSON string).

---

## Dependencies

Poetry, with an in-project `.venv` (`poetry.toml`: `in-project = true`). Add
dependencies with `poetry add <pkg>` (dev: `poetry add --group dev <pkg>`) —
never hand-edit `pyproject.toml` or `poetry.lock`. Run all code, scripts, and
tests via **`poetry run`** (`poetry run uvicorn ...`, `poetry run pytest`),
never a bare `python3` or the raw `.venv/bin/*` entrypoints.

---

## Tests

Run the suite with `make test`. No live DB is required — every test is pure or
runs against an in-memory fake. The worker stages are covered by
`tests/test_worker_*.py` (pure transforms, funnel, enricher, scanner, the tick,
and the resource lock) against `tests/worker_fakes.py` — no DB or provider key
needed. Pure-logic tests (big_group, parent_gym_type, schema round-trips, the
DB-URL normaliser, …) round out the suite. Round-trip every gym file with
`make gym-check GYM_ID=all` before committing.

---

## What NOT to do

- Do not hardcode gym-specific names, disciplines, or search prompts in Python.
  Anything specific to one gym belongs in `gyms/<gym_id>.yaml`.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not add scraping or scanning calls to `schema/` — the whole
  scrape → funnel → enrich → scan → feed-write pipeline lives in `src/worker/`.
  There are two write paths into the shared Postgres: the **worker** writes the
  pool + RAG + feed + runs + cost log through its own `src/worker/sql/`, and
  `make sync-gyms` (which also runs `scripts.import_yaml`) loads the YAML gym
  configs + the pool + the **template RAG sidecar** (`video_rag/` → `video_rag`)
  through `scripts/shared/video_db_writer.py` (`scripts/sql/`). The one-time
  `make enrich-templates` run is NOT a DB write path — it READS the pool and WRITES
  the untracked-local sidecar file that `import_yaml` then loads.
- Do not un-guard **any** column in `scripts/sql/upsert_video.sql`'s
  `ON CONFLICT … DO UPDATE SET`. The `videos/` YAML pool is **legacy** and that
  import re-runs on every `make sync-gyms`, so an unguarded `= EXCLUDED.…` silently
  destroys live data: 4,084 YAML files carry `tag: null` (each would wipe a paid
  enrich-stage tag), 4,040 carry `transcript: null` (paid Apify transcripts), every
  file carries an empty avatar, and 22,831 carry the weak `@handle`-form
  `channel_url` while the worker writes the canonical `/channel/UC…` id form. The
  file therefore **mirrors the worker's own merge-upsert**
  (`src/worker/sql/worker_upsert_video.sql`) column for column — `tag` /
  `disciplines` omitted from the SET (the enrich stage owns them), `transcript`
  COALESCEd onto the stored one, `source_queries` UNIONed, `relevance_index` kept at
  its best (LEAST), counts/duration COALESCEd, and the two channel columns guarded
  so a stored value can only ever be UPGRADED, never degraded. Keep the two files in
  agreement; if the worker's semantics change, change the import with them.

---

## Jobs / workflow

Two kinds of job. **Gym-config tooling** (author YAML + load it into SQL) runs as
`scripts/` modules + `make` targets; the **content pipeline** runs as the background
worker:

1. **Make/edit a gym** (`make gym-check GYM_ID=<id|all>`) — author/update
   `gyms/<gym_id>.yaml` and validate it round-trips the `Gym` schema (YAML-only).
2. **Sync gyms → SQL** (`make sync-gyms GYM_ID=<id|all>`) — upsert the authored
   gym files into `template_gym` + its query/class/reward child tables, then load
   the existing `videos/` pool + the **template RAG sidecar** (`video_rag/` →
   `video_rag`, see below) + each gym's good/rejected feeds into SQL (pool +
   video_rag upserts, feeds rewrite per gym — no re-scrape). Fully idempotent. It
   runs the import with `--skip-cost-log`, so the append-only `cost_log.yaml` is
   **not** imported here (re-running would duplicate ledger rows); load it once by
   hand with `poetry run python -m scripts.import_yaml.run` if you need the history.
   These write through `scripts/shared/video_db_writer.py` + `scripts/sql/` and
   pick their DB via the **`ENV_FILE`** flag (default `.env`; `ENV_FILE=.env.prod`
   targets prod) — see `scripts/shared/db_target.py`.
3. **Enrich the templates → RAG sidecar** (`make enrich-templates`) — a **one-time,
   PAID** run that builds the artifact step 2 loads. The unified feed gates on a
   `video_rag` row (an embedding) being present, so a freshly-imported preset feed
   would look empty until the worker's enrich sweep caught up. This run enriches
   the **~18.9k unique template videos** referenced in `template_gym_feed` (both
   verdicts) ONCE — reusing the worker enricher's per-video unit
   (`WorkerEnricher.enrich_one`: one multimodal summary+tag+disciplines+facets call fed a
   per-chunk BATCHED Apify transcript fetch — usually a no-op, templates are ~100% cached)
   plus a summary embedding — and appends each to
   the **untracked-local sidecar** `video_rag/video_rag.jsonl` (base64-packed
   float32 embeddings; ~330 MB at 3072 dims, distributed to prod via S3 exactly like `videos/`).
   `import_yaml` then reloads it into `video_rag` on every sync (upsert by
   `video_id`, `ON CONFLICT DO NOTHING` — SEEDS, never clobbers a live worker
   enrichment). Because `video_rag` is keyed by `video_id` and shared across the
   template pool AND every real gym, seeding it for template videos enriches every
   gym that later imports a preset **for free**. It only READS the DB (the pool
   fields) and WRITES the sidecar file — never mutates the DB — and is
   resumable/idempotent (skips videos already in the sidecar). Needs the keys the
   configured `enrich_model` + `embedding_model` use — both Gemini now, so just
   `GEMINI_API_KEY` — plus `APIFY_TOKEN` for the lazy transcript fetches, and a DB
   already synced (pool + `template_gym_feed` loaded). The sidecar format is owned by
   `scripts/shared/video_rag_sidecar.py`. **Smoke-test first:** `make
   enrich-templates ARGS="--limit 1 --root /tmp/enrich_smoke"` runs the whole
   enrich→embed→sidecar pipeline on ONE video (into a throwaway root) to prove it
   works before the full paid run.
4. **Backfill the creator avatars** (`make backfill-avatars`) — a **one-time**,
   $0 (quota-only) run that gives the pre-existing pool what the worker's avatar
   pass now gives every new scrape. Two passes, both derived from current table
   state and therefore resumable + idempotent: **pass 1** recovers each legacy
   `@handle` channel's real id via `videos.list?id=<one of its videos>` →
   `snippet.channelId` (grouped per CHANNEL, ~231 calls for 11,502 handle channels —
   not per row) and rewrites its rows to the canonical `/channel/UC…` URL, which
   permanently removes the legacy handle data; **pass 2** fills the avatars via
   `channels.list?id=` (~236 calls), reusing the worker's `WorkerAvatarResolver`
   outright so there is ONE `channels.list` implementation and ONE avatar write path.
   ~467 quota units total against a 10,000/day budget, no re-scrape, no LLM call. A
   channel some sibling row already knows the avatar for is copied with no API call.
   `--limit N` caps the channels per pass for a smoke test; `ENV_FILE` picks the DB.
   It cooperates with the import guards above: those block a re-import of the legacy
   YAML from downgrading an upgraded URL or blanking a filled avatar, while still
   allowing the upgrade itself, so `make sync-gyms` can never undo it.
5. **The content worker** (`make worker` → `python -m src.worker.run`) — the
   decoupled scrape / enrich / scan step worker (cleanup → finalize → one drained
   step per tick), detailed in the next section. It **replaced** the old standalone
   `scripts/scraper` + `scripts/scan` jobs (both deleted, along with
   `src/classification`); it writes through its own `src/worker/sql/`, not
   `VideoDbWriter`.

---

## The background worker (`src/worker`)

A standalone long-running process — `python -m src.worker.run` (`make worker`) — that
keeps every gym's feed and the shared RAG layer current. **Not a web server, no port.** It
is the video half of the combined `deploy/` container (the other half is FastApiBackend's
uvicorn). **There is no job queue and no control surface** — the worker is fully
self-scheduling: it derives its own work each tick straight from timestamps already in the
schema (`video_run`, `gym_video_spec`, `gym_video_feed`). The FastApiBackend never triggers
a run and there is **no worker status/control endpoint** — the two systems never call each
other; the backend only *reads* the same `video_*` rows the worker writes. The flow is
diagrammed in `worker.mermaid` at the VideoService root (a docs task owns that file; keep
this section and the diagram in agreement, and edit the diagram with the `mermaid-creation`
skill).

**The re-architecture: independent DB-backed steps, one per tick.** A tick no longer runs
one gym end-to-end. Instead each step reads its own work from the DB and is idempotent, so
the steps are decoupled and crash recovery is free. Feed rows are written at **scrape** time
as `pending`; a global **enrich** sweep gives every un-enriched video a `video_rag` row; a
global **scan** sweep settles each `pending` row to `accepted`/`rejected`.

### The tick

`run.py` is a loop: `WorkerService.run_tick`, then wait `worker_poll_seconds` (60). Each
tick takes the global TTL lock `"video_worker_run"` on the shared `resource_locks` table
(single-shot, non-blocking — a second worker no-ops the tick; TTL `worker_lock_ttl_seconds`
1800s (30 min — long holds are expected), renewed by a `worker_heartbeat_seconds` (300s)
heartbeat that MUST stay well under the TTL; a lost heartbeat sets the abort flag and the
current drain stops between videos/batches/gyms). Then, under one lock hold, IN ORDER:

1. **Cleanup** (always, cheap) — `DELETE FROM video WHERE failure_count >= worker_failure_max`
   (3). The FK cascades remove the video's feed rows, `video_rag` row, and member recs. Runs
   FIRST so the finalize step's denominators reflect the shrunk feed.
2. **Finalize** (always, cheap) — complete/fail every `running` run purely from its feed
   rows (below). Runs are long-lived now, so a separate step decides when one is done.
3. **One heavy step, first-with-work, drained fully** — check **scan**, then **enrich**, then
   **scrape** (backlog first; scrape is the quota-bound ingest, so it goes last). The first
   step that has work is DRAINED COMPLETELY this tick, then the tick ends. If none has work
   the tick ends.

**There is NO orphan rule.** `running` is a legitimate long-lived multi-tick state (a run
full of `pending` rows the sweeps are still chewing through), so a `running` run is never
treated as dead. Crash recovery is free — every step is DB-derived + idempotent, and the
finalize 0-row / TTL guards catch any pathologically stuck run.

### Finalize (complete / fail runs from their feed rows)

Two SQL passes, IN ORDER (completion beats the TTL fail):

1. **complete** (`worker_finalize_complete.sql`) — a `running` run whose **terminal**
   fraction reaches `worker_run_complete_fraction` (0.9) is completed. terminal = feed rows
   with `scan_status IN ('accepted','rejected')`; denominator = ALL the run's feed rows.
2. **fail** (`worker_finalize_fail.sql`) — a `running` run with **zero** feed rows older
   than `worker_zero_row_grace_hours` (1h) → `failed`, `error='no feed rows'`; else a run
   older than `worker_run_ttl_hours` (24h) that never reached the completion fraction →
   `failed`, `error='run ttl exceeded'`.

### The lifecycle: pending → enriched → scanned

- **scrape** (per-gym, quota-bound — the ONLY step that opens runs, so the run caps bound
  exactly the quota-limited work). It selects the due gym (`worker_select_due_gym.sql` — due
  on a newer `admin_update` spec version than the last **COMPLETED** run (tier 1 — a FAILED
  scrape does NOT suppress this trigger, so a transient error is retried, bounded by the run
  caps) or the weekly refresh floor (tier 3, vs the last run of any status); a manual
  `gym_video_feed` curation triggers no SCRAPE here — the feed-learning re-scan off a manual
  curation is the SCAN step's arm B (below), an in-place re-judge of existing feed rows, not a
  new scrape run; the query also excludes any gym with a `running`
  run — never two in-flight runs. A scrape that raises after the run is opened marks that run
  `failed` (`worker_fail_run.sql`) so no phantom `running` run strands the gym), loads the
  latest spec + incremental context (`WorkerSpec`),
  opens a `video_run` (`running`),
  runs the **YouTube Data API v3** scrape (two calls per query, merge-upserted into the
  `video` pool — `source_queries` accumulate, `tag`/`disciplines`/`transcript` never wiped),
  then runs the **creator-avatar pass** (below),
  and picks candidates via the two-tier **funnel** (tier-1 query+discipline overlap incl.
  untagged fresh scrapes with incremental exclusion, tier-2 RAG probe up to
  `scan_budget_per_run`). Then the **feed write** (`WorkerScraper.write_feed`): carry the
  previous completed run's rows forward FIRST (ALL rows incremental / manual-only fresh —
  `worker_carry_forward.sql`, which also carries each row's `scanned_at` watermark so arm B
  does not re-judge the whole carried feed against an already-consumed `feed_update`), then
  insert every candidate as a `pending` row
  (`worker_insert_pending.sql`, `curation_type='automatic'`) `ON CONFLICT DO NOTHING` so a
  carried row always wins. The run is left `running`; nothing is enriched, scanned, or
  completed here.
- **enrich** (global, gym-agnostic sweep — `WorkerEnricher.drain`). Targets
  (`worker_enrich_targets.sql`) = videos that LACK a `video_rag` row and are under the strike
  ceiling, drawn from each gym's **latest non-failed run** (`pending`/`accepted` rows — skip
  `rejected`; `accepted`-without-rag are imported presets / pre-RAG carry-forwards that must
  get an embedding) ∪ ALL owner-section rows (`video_run_id IS NULL`). Per chunk: a BATCHED
  Apify transcript fetch of the chunk's cache-misses in ONE actor run (miss → placeholder,
  NOT a strike), then per video ONE multimodal `enrich_model` call
  (thumbnail + metadata + transcript slice → genre `tag`, disciplines, a **detailed**
  summary, facets), tags written to `video`, summaries batch-embedded into `video_rag`
  (concurrency `worker_enrich_concurrency`, 8). The enrich call is the ONLY step that sees
  the thumbnail + transcript — its summary must fold in the visual + content detail because
  scan reads only that summary (below).
- **scan** (global sweep, per-gym batches, **TEXT-ONLY** — `WorkerScanner.drain`). Targets
  (`worker_scan_targets.sql`) = enriched feed rows (video HAS a `video_rag` row) under the
  strike ceiling, matching EITHER arm: **(A)** a `pending` row in the gym's **latest non-failed
  run** (its first verdict), OR **(B)** the **feed-learning RE-SCAN** — a `curation_type='automatic'`
  row in the gym's **latest COMPLETED (served) run** (arm B targets the served run, NOT the
  latest non-failed, so an in-flight `running` run never diverts the re-judge from what members
  see) whose `scanned_at` predates a gym `feed_update` `gym_video_spec`
  version that has SETTLED ≥ `worker_feed_update_rescan_delay_hours` (1h) (`created_at <= now()
  - the delay` AND `created_at > COALESCE(scanned_at, '-infinity')`). Per gym: load the
  **latest** spec at scan time (judge against current criteria — the `feed_update` folded in the
  owner's manual keep/avoid signals), batch by `scan_batch_size` (12), and run keep/drop on each
  candidate's **summary + structured enrich outputs** (genre, disciplines, facets) — NO thumbnail
  is re-sent, since enrich already folded the visual detail into the summary. Text-only is cheaper
  AND matters because scan runs per-gym (a video in many feeds is scanned many times) while enrich
  runs once per video. Verdicts are written by UPDATE (`worker_update_verdict.sql`) keyed by each
  row's OWN `video_run_id` (arm A and arm B can select rows from different runs for the same gym)
  and guarded on
  `curation_type <> 'manual'` — an owner's explicit keep/reject verdict is never overwritten, and
  a row is never flipped to `pending` (which would blank it from the served feed); the UPDATE
  stamps `scanned_at = now()` so the same `feed_update` never re-triggers a row (arm B flips
  accepted↔rejected only when the judgment changes). This zero-downtime in-place re-scan is the
  worker half of the **`feed_update` auto-learn loop** — its backend half is the immediate,
  coalesced auto-refine that mints the `feed_update` version on a manual curation (see the
  FastApiBackend `videos` domain).

### Creator avatars (`src/worker/worker_avatars.py`) — part of the scrape step

**Creator avatars ARE a product feature.** The member UI shows the creator's
circular avatar beside a video's title, and `video.channel_avatar_url` is filled by
the worker — not left empty. Two writers exist: this pass, and the backend's
owner-added-video path (its own `channels.list` lookup).

A `search.list` / `videos.list` snippet carries the channel **id** but no avatar, so
the scrape resolves it with a third call: `channels.list?part=snippet&id=<≤50 ids>`
→ `snippet.thumbnails` (`high` → `medium` → `default`), **1 quota unit per call
regardless of batch size**. The pass runs AFTER the pool merge (the rows must exist
to be written) and writes by **`channel_url`, never by video id** — the avatar is a
per-CHANNEL property stored redundantly on each of the channel's ~2 pool rows, so a
video-keyed write would leave the rest of the channel stale.

**It refreshes, it does not only fill.** A `yt3.ggpht.com` URL is content-addressed:
when a creator changes their picture the old URL eventually 404s, and a dead URL
renders worse than no avatar. So the pass re-resolves **every** channel the scrape
touched, not only the uncovered ones. Because every gym re-scrapes at least weekly
(the tier-3 refresh floor), a channel that still surfaces in any gym's queries is
refreshed at least weekly at ~0 cost. The residual gap — a feed row whose channel no
longer ranks for any query is never revisited — is accepted deliberately: closing it
needs a per-channel `refreshed_at` timestamp the flat per-video `video` table has no
place for, which is a schema decision (founder-ops), not a worker one.

Cost + bounds: a run surfaces ~600 distinct channels → ~12 quota units, against the
~2,500 the same run spends on `search.list`. `worker_avatar_max_batches` (40) is a
hard ceiling on the calls one scrape may spend; when it binds, channels with NO
avatar are resolved before ones being refreshed
(`worker_channel_avatar_state.sql`). Those units are counted INTO the run's
`youtube_quota_units` and broken out in the `cost_log` `search` row's breakdown
(`avatar_quota_units`, `channels_resolved`) — the avatar pass is never uncounted
quota. Failure posture matches the scrape's: a 403/quota error on a batch is logged
and dropped, never raised; the attempted call is still charged.

**No `channel_id` column.** The worker has the id in memory at scrape time
(`snippet.channelId`), and every stored id-form `channel_url` yields it back by
regex (`worker_transforms.channel_id_from_url`). A column would be a second copy of
data already on the row, duplicated per video, needing its own migration + backfill
+ sync discipline.

### The strike / cleanup mechanic (`video.failure_count`)

Hard errors only, and ONLY the expensive multimodal pass. In the enrich sweep a video whose
multimodal call raises is bumped (`worker_bump_failure.sql`); a chunk whose EMBED call raises is
**NOT** struck — the multimodal enrich already succeeded, so those videos are left un-enriched
(no `video_rag` row) to retry the embed next sweep, since striking them for an embed flake would
push an already-enriched video toward deletion. In the scan sweep a batch whose LLM call
raises bumps EVERY video in the batch and leaves the rows `pending` (retried next sweep — **no
default-to-rejected**), and a video the model omits from an otherwise-successful batch is
bumped alone and stays `pending`. A missing transcript is **not** a strike. On success —
enriched, or verdicted — the counter is reset to 0 (`worker_reset_failure.sql`). The cleanup
step deletes a video at `worker_failure_max` (3) strikes.

### Cost logging (`cost_log`, attributed per step)

Spend goes to the generic **`cost_log`** table (shared across cost-bearing systems — see
`../Database/CLAUDE.md`), each row stamped `source='video'`, `stage`, `model` (NULL for the
free `search` stage and the Apify `transcript` stage), `cost_usd`, and a `breakdown` map.
Attribution differs by step: **scrape** logs `search` (free; quota-units diagnostic —
the TOTAL, `search.list` plus the avatar pass's `channels.list`, with the avatar
share broken out as `avatar_quota_units` / `channels_resolved`) +
`embed` (tier-2 probe), both keyed to that gym + run; **enrich** logs `transcript` +
`enrich` + `embed` as **pool-level** rows (`gym_id` and `run_id` NULL — a swept video is
shared across gyms, so per-gym attribution would be arbitrary); **scan** logs one `scan` row
per gym per sweep, keyed to that gym + its latest run. **Cost logging is durable across abort:**
the enrich sweep and each gym's scan accumulate spend and flush the cost row in a `finally`, and
a failing scrape logs its incurred cost in a `finally` too — so an abort (lost lease) or an
exception mid-step still records the dollars already spent rather than dropping the cost row.

### Settings + the embedding contract

Worker knobs live in `src/worker/worker_config.py` (`WorkerSettings`) — the models above,
scheduling (`worker_cap_window_hours` (24), `worker_gym_run_cap` (2),
`worker_system_run_cap` (5), `worker_weekly_refresh_days` (7)), the strike ceiling + run finalize
(`worker_failure_max` (3), `worker_run_complete_fraction` (0.9),
`worker_run_ttl_hours` (24), `worker_zero_row_grace_hours` (1)), the feed-learning
re-scan wait (`worker_feed_update_rescan_delay_hours` (1.0) — how long a `feed_update`
spec version must settle before the scan sweep re-judges the gym's auto feed rows against
it, threaded as the `:rescan_delay_hours` bind in `worker_scan_targets.sql`), budgets
(`scan_budget_per_run`, `scan_batch_size`, `worker_enrich_batch_size` (64 — enrich sweep
chunk == embed batch), `rag_probe_top_k`,
`worker_avatar_max_batches` (40 — the hard ceiling on `channels.list` calls one
scrape may spend on creator avatars),
`enrich_transcript_char_budget`), concurrency (`worker_scrape_concurrency`,
`worker_enrich_concurrency` — the scan sweep is strictly sequential, no concurrency knob), the lock/loop
timers, the LLM client knobs the worker's `LiteLLMClient` construction sites pass down
(`llm_request_timeout_seconds` (90), `llm_num_retries` (5), `llm_retry_backoff_seconds`
(5, 15) — `LiteLLMClient` itself only owns the module-level *defaults* used when a
caller builds one with no overrides), the `youtube_api_key` (YouTube Data API v3,
discovery + metadata + creator avatars) + `worker_youtube_timeout_seconds` (30s), and the
Apify transcript knobs — `apify_token`, the batched actor pricing
(`apify_transcript_cost_per_transcript_usd` $0.0005 + `apify_actor_start_cost_usd`
$0.001), `apify_transcript_batch_size` (64), and the LONG/conservative
`.call()` bounds `apify_run_wait_seconds` (900s) + `apify_fetch_deadline_seconds`
(1200s) that stop the batched transcript fetch from hanging the worker (the enrich
sweep batch-fetches a chunk's missing transcripts in ONE
`supreme_coder/youtube-transcript-scraper` run). It reads `DATABASE_URL` from
`src/shared/config.py` and the LLM provider keys
(`gemini_api_key`, `openai_api_key`, `anthropic_api_key`) from `src/core/config.py` — three
`Settings` classes over the one `.env`.

The **embedding contract is cross-service.** The worker embeds with
`embedding_model` (`gemini/gemini-embedding-001`, native 3072) into `video_rag.embedding` typed
`vector(3072)`; `run.py` asserts `embedding_dim == 3072` at startup. The FastApiBackend RAG
readers (member recs + personalized feed) rank against those same `video_rag` embeddings, so
both sides pin the **same model + `vector(3072)` dimension** (`settings.video_embedding_dim`
on the backend). The embedding is stored full precision; only the `video_rag` HNSW index runs on
a `halfvec(3072)` cast (the `vector` type can't HNSW past 2000 dims), so the worker's Tier-2 funnel
probe casts to `halfvec` to use it. Changing the model/dim is a one-way door — a coordinated
re-embed of BOTH sides — and changing one without the other silently breaks similarity.
