---
name: video-config-guide
description: >-
  The single source of truth for the CombatDen video-config AGENT system — the
  LLM-backed authoring of a real gym's video configuration (its keep/avoid
  criteria + YouTube search queries) in the FastApiBackend `src/video_config/`
  domain. Covers the APPEND-ONLY VERSIONED `gym_video_spec` model (spec_id PK,
  `queries` JSONB, `source` enum, the `gym_video_spec_latest` read view), the
  three writers that mint versions (the conversational agent = `admin_update`,
  the preset import = `system_update`, the feed-learning refiner = `feed_update`),
  the feed→spec LEARNING LOOP (the core promise — manual curation on
  `gym_video_feed` is folded into an improved spec version), and the Pydantic AI
  integration (provider-swappable via a model string, `defer_model_check`, and
  why litellm is NOT used). Load this whenever you touch anything video-config
  shaped: `gym_video_spec` / `gym_video_spec_latest` / `gym_video_query` (dropped),
  the agent / query generator / feed refiner, the `video-config` endpoints, the
  prompts in `src/video_config/prompts/`, the `video_agent_model` setting, or the
  feed `curated_at` signal. Trigger on "video config", "video agent", "query
  generator", "spec version", "feed_update / admin_update / system_update",
  "refine from feed", "gym_video_spec", "Pydantic AI", "video_agent_model", or any
  change to the video-config data model, endpoints, prompts, or learning loop.
---

# Video-config agent — the versioned, LLM-authored spec model

This is the deep domain knowledge for how a real gym's **video configuration** is
authored. It is the **source of truth** for the design; `FastApiBackend/CLAUDE.md`
holds only the lean "how to work here" summary. When the model, endpoints, or
learning loop change, **update this skill in the same change** (it is a living
document — see the bottom).

**Scope.** "Video config" = the two things the (separate, future) scrape/scan
**worker** consumes: a gym's `videos_desc`/`avoid_desc` keep/avoid criteria and its
search `queries`. This skill is about *authoring and modifying* that config. The
worker that runs the scrape/scan against it is out of scope (later). The old
single-tenant pipeline (make-a-gym / scrape / scan over YAML) is a *different*
system — see the `videoservice` skill under `VideoService/.claude/skills/`.

## 1. The spec is APPEND-ONLY VERSIONED — readers use the view, never the table

`gym_video_spec` is a permanent **version log**, one row per *version* of a gym's
config (not one row per gym). Columns: `spec_id UUID PK`, `gym_id UUID FK`,
`gym_type JSONB` (disciplines, a JSON string array — `gym_type[0]` is primary),
`videos_desc` / `avoid_desc` (the long keep/avoid **scan criteria**),
`short_videos_desc` / `short_avoid_desc` (display-only), **`queries JSONB`** (the
search list — a JSON string array), **`source gym_video_spec_source`** (what minted
the version), `imported_from` (template-slug provenance, NULL once agent/hand
authored), `created_at`.

- **Rows are NEVER `UPDATE`d.** Every change is a new `INSERT`. History is retained.
- **Every read takes the latest version** via the view
  **`gym_video_spec_latest`** = `SELECT DISTINCT ON (gym_id) * … ORDER BY gym_id,
  created_at DESC, spec_id DESC`. The view is `security_invoker = true` so the base
  table's RLS (employee/member SELECT policies) applies to the caller. **Never
  `SELECT` from the raw `gym_video_spec` table in a read path** — use the view.
- **Queries live in the spec's `queries` JSONB** — there is no separate query
  table. (`gym_video_query` was dropped when versioning shipped; its rows were
  folded into `queries`.)
- JSONB read/write convention: write `json.dumps(list)` bound + `CAST(:p AS JSONB)`;
  read with an `_as_list` normaliser (the asyncpg driver may hand back a decoded
  list OR a raw JSON string).

## 2. Three writers — `source` records who minted each version

`gym_video_spec_source` ∈ `{admin_update, system_update, feed_update}`:

| source | minted by | how |
|---|---|---|
| `admin_update` | the conversational agent / a direct owner save | `PUT /api/v1/gyms/{gym_id}/video-config` (`VideoConfigService.save_draft`) |
| `system_update` | the preset import | `PresetsService` → `presets_insert_spec_version.sql` (one versioned row, queries folded from the `video_gym` template) |
| `feed_update` | the feed-learning refiner | `VideoConfigService.refine_from_feed` (§4) |

All three write at **service_role** (clients never write the table; RLS revokes
INSERT/UPDATE/DELETE from `authenticated`). The agent path is gym-employee gated at
the app layer.

## 3. The conversational agent + the query generator

- **Agent** (`src/video_config/service/video_config_agent.py`,
  `build_video_config_agent`): a Pydantic AI `Agent` with
  `output_type=[str, VideoConfigDraft]` — it returns **free text** (its next
  interview question) until it has enough, then a structured **`VideoConfigDraft`**
  (disciplines + criteria + queries) for the owner to confirm. Two tools:
  `generate_queries` (→ the query generator) and `read_current_config` (latest spec,
  so it can *modify*, not only create). System prompt:
  `prompts/video_config_agent_system.md`.
- **Query generator** (`video_config_query_generator.py`,
  `VideoConfigQueryGenerator.generate`): **one structured LLM call**
  (`output_type=QueriesResult`) that maps disciplines + criteria → search queries
  **spread across the nine video genres** (about half teach/how-to, the rest
  enjoy + human + peak). It is used by BOTH the agent's `generate_queries` tool AND
  the standalone `POST …/generate-queries` endpoint, so the genre-spread logic lives
  in one place. Prompt: `prompts/video_config_query_generator.md` (a `string.Template`
  with `$disciplines`/`$videos_desc`/`$avoid_desc`/`$count`).
- **Draft → confirm → save.** The agent never writes; the owner confirms a
  `VideoConfigDraft`, which `PUT …/video-config` appends as an `admin_update` version.
- **Stateless conversation.** The server holds no session — each turn the client
  sends back the serialized `history` it got last turn (`ModelMessagesTypeAdapter`),
  and gets the new history to send next.

## 4. The feed→spec LEARNING LOOP (the core promise)

The spec *learns* from how the owner curates their feed. When an owner manually
rejects / un-rejects / re-adds a video in `gym_video_feed`, that action bumps
**`gym_video_feed.curated_at = now()`** (manual paths only — the automatic scan and
preset seed leave it NULL). Those are the learning signals.

`VideoConfigFeedRefiner.propose(gym_id, current)` (`video_config_feed_refiner.py`):

1. Loads the gym's **unconsumed** signals — feed rows where `curated_at IS NOT NULL`
   AND `curated_at > COALESCE(max(created_at) of the gym's last 'feed_update'
   version, '-infinity')` (`video_config_load_feed_signals.sql`), joined to `video`
   for title/channel.
2. **No signals → returns `None`** (nothing new to learn; no version minted).
3. Otherwise renders the signals (a manual **reject** = criteria wrongly INCLUDED →
   tighten; a manual **keep/re-add** of a scan-rejected video = criteria wrongly
   EXCLUDED → widen) + the current spec into `prompts/video_config_feed_refine.md`
   and runs a single structured call → an improved **`VideoConfigDraft`** touching
   **both criteria AND queries**.

`VideoConfigService.refine_from_feed` then saves that draft as a `feed_update`
version. It is **batched**, not per-action (feed clicks stay instant; they only
record `curated_at`). Triggers: **pre-agent-view-open** (the CRM calls
`POST …/refine-from-feed` right before the owner starts editing, so the spec already
reflects recent curation) and **pre-worker-run** (the future worker calls the same
service before scanning — build now, wire later).

## 5. Endpoints — `/api/v1/gyms/{gym_id}/video-config` (all gym-employee gated)

| Route | Purpose |
|---|---|
| `GET /` | the gym's latest config (`gym_video_spec_latest`); 404 if none yet |
| `POST /agent` | one conversational turn — `{message, history}` → `{reply?, draft?, history, usage?}` |
| `POST /generate-queries` | the single-call query generator; omitted inputs default to the gym's spec |
| `PUT /` | confirm/save a `VideoConfigDraft` → a new `admin_update` version |
| `POST /refine-from-feed` | fold unconsumed curation → a `feed_update` version; 404 if no spec or nothing new |

## 6. Pydantic AI — provider-swap, `defer_model_check`, and why NOT litellm

- **Framework: Pydantic AI** (`pydantic-ai-slim[anthropic]`), not litellm.
  **litellm does not install on the backend's Python 3.14** (fastuuid/grpcio/uvloop);
  Pydantic AI does, and is Pydantic-v2/FastAPI-native. (The *future worker*, running
  on its own Python, may still use litellm.)
- **Provider-swappable via a string.** `settings.video_agent_model` (default
  `anthropic:claude-sonnet-4-6`) is the swap point — change it to any provider
  Pydantic AI supports (`openai:…`, `google-gla:…`) whose key is set. Keys
  (`anthropic_api_key` / `openai_api_key` / `gemini_api_key`) live in `Settings`;
  the DI builders in `video_config_llm.py` publish the non-empty ones to the env
  (`configure_provider_keys`, `setdefault`) because Pydantic AI reads provider keys
  from the environment.
- **`defer_model_check=True`** on every agent — the model (and its key) resolve at
  call time, so **the backend boots with NO key set**; only the LLM endpoints fail
  (500) until `ANTHROPIC_API_KEY` is in `FastApiBackend/.env`.
- **Prompts live in `.md`** (`src/video_config/prompts/`), read at use — never
  inlined in code (monorepo rule).
- **Cost ledger:** agent/refiner spend is **not** written to `video_cost_log` (its
  `execution_type` enum is scrape/scan-shaped and its `gym_id` FKs the *template*
  table). Token `usage` is surfaced in the agent response + logs; a proper
  agent-cost ledger is deferred, not force-fit.

## 7. Testing without a key or a DB

Use Pydantic AI test models (no provider key, no network): `TestModel` (auto valid
output — yields the **str** reply path), and `FunctionModel` emitting the output
tool to force the **`VideoConfigDraft`** path. Override a built agent with
`with agent.override(model=TestModel()): …`. DB-touching reads/writes need the
migration applied; pure agent/generator/refiner logic is tested with stubs. See
`tests/video_config/`.

## Key files (where the model actually lives)

- Schema: `Database/supabase/schemas/gym_video_spec.sql` (table + `…_source` enum +
  `gym_video_spec_latest` view), `gym_video_feed.sql` (`curated_at`);
  `Database/python_data/schema/video.py` (`GymVideoSpecSource` mirror).
- Domain: `FastApiBackend/src/video_config/` — `video_config_router.py`,
  `schema/video_config_schema.py`, `service/{video_config_service, video_config_agent,
  video_config_query_generator, video_config_feed_refiner, video_config_llm}.py`,
  `prompts/*.md`, `sql/*.sql`.
- Writers elsewhere: `src/presets/service/presets_service.py` +
  `presets_insert_spec_version.sql` (`system_update`); feed `curated_at` bumps in
  `src/videos/sql/{videos_reject_feed_video, videos_keep_feed_video,
  videos_insert_feed_video}.sql`.
- DI: `src/core/dependencies.py` (`video_config_*` providers); settings in
  `src/core/config.py`.
- CRM consumer: `CRM/lib/features/video_config/` (screen + Bloc + chat/draft
  widgets) and `CRM/lib/features/members/data/video_config_repository.dart`; entry
  point in the settings screen. It calls `refine-from-feed` on open (with a brief
  loading state), runs the chat, and saves a confirmed draft via `PUT`.

## This is a living document

When the spec model, the writers, the learning loop, the endpoints, the prompts, or
the Pydantic AI wiring change, update this skill **in the same change** — and keep
the lean `FastApiBackend/CLAUDE.md` `video_config` section in sync too. A stale skill
produces false "violation" findings in review and misleads the next contributor.
