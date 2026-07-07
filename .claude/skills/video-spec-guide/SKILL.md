---
name: video-spec-guide
description: >-
  The single source of truth for the CombatDen video-spec AGENT system — the
  LLM-backed authoring of a real gym's video configuration (its keep/avoid
  criteria + YouTube search queries) in the FastApiBackend `src/videos/`
  domain. Covers the APPEND-ONLY VERSIONED `gym_video_spec` model (spec_id PK,
  `queries` JSONB, `source` enum, the `gym_video_spec_latest` read view), the
  three writers that mint versions (the conversational agent = `admin_update`,
  the preset import = `system_update`, the feed-learning refiner = `feed_update`),
  the LLM SPLIT (litellm via LiteLLMClient for VideoQueryGenerator /
  VideoFeedRefiner structured calls — query gen is a two-call landscape→queries
  flow; Pydantic AI for the VideoAgentService conversational agent only — Python
  3.13, litellm can't run on 3.14),
  the NO-TOOLS ACCEPT-PATH model (agent proposes criteria-only VideoSpecDraft or
  multi-choice AgentQuestion; accept sends accepted_spec in the POST body;
  VideoSpecAuthoring.commit runs the deterministic diff-guard → query-gen → save),
  and the ONE-WAY LAYERING rule (agent → facade → regular services; never reverse).
  Load this whenever you touch anything video-spec/agent shaped: `gym_video_spec` /
  `gym_video_spec_latest` / the agent / query generator / feed refiner / the
  `/video-spec` or `/video-agent` endpoints / the prompts in
  `src/videos/prompts/` / `video_llm_model` / `video_agent_model` / the feed
  `curated_at` signal. Trigger on "video spec", "video agent", "query generator",
  "spec version", "feed_update / admin_update / system_update", "refine from
  feed", "gym_video_spec", "Pydantic AI", "litellm", "LiteLLMClient",
  "VideoSpecAuthoring", "AgentQuestion", VideoSpecService, VideoQueryGenerator,
  VideoFeedRefiner, VideoAgentService, or any change to the video spec/agent data
  model, endpoints, prompts, or learning loop.
---

# Video-spec agent — the versioned, LLM-authored spec model

This is the deep domain knowledge for how a real gym's **video configuration** is
authored. It is the **source of truth** for the design; `FastApiBackend/CLAUDE.md`
holds only the lean "how to work here" summary. When the model, endpoints, or
learning loop change, **update this skill in the same change** (it is a living
document — see the bottom).

**Scope.** "Video spec" = the two things the VideoService scrape/scan **worker**
(`VideoService/src/worker`) consumes: a gym's `videos_desc`/`avoid_desc` keep/avoid
criteria and its search `queries`. This skill is about *authoring and modifying*
that config; the worker that runs the pipeline against it is out of scope here (see
the `videoservice` skill under `VideoService/.claude/skills/`). The worker has **no
control surface** and is never triggered by the authoring path — it is fully
self-scheduling, deriving its own due gym each tick from timestamps already in the
schema (an `admin_update` spec version, a settled manual feed curation, or a weekly
refresh floor; below). The domain also grew a RAG read surface (member recs +
semantic search) that ranks against the worker's `video_rag` embeddings — out of
scope here; see `FastApiBackend/CLAUDE.md`.

## 0. Architecture: LLM split, general services, thin agent, one-way layering

The spec/agent surface lives inside the **`videos` domain** (`src/videos/`). The
general services are NOT written for the agent — they are independently useful and can
be called directly from routes:

- **`VideoSpecService`** (`service/video_spec_service.py`) — spec DB read/write:
  `load_latest` (via `gym_video_spec_latest` view) and `save_version` (append-only
  INSERT). No LLM dependency.
- **`VideoQueryGenerator`** (`service/video_query_generator.py`) — **litellm**
  structured query gen, a **two-call** flow: call 1 researches the niche's content
  landscape (`LandscapeResult` — channels / creators / series_events, from the
  model's own knowledge, hallucination tolerated, never validated); call 2 turns
  criteria + that rendered landscape into `QueriesResult` (~one third of queries
  name-targeted at the landscape, the 5-cluster genre spread governing the whole
  set). Both calls use `LiteLLMClient.complete_structured` with
  `settings.video_llm_model`; `count` is injected by `VideoSpecAuthoring` from
  `settings.video_query_count` (30). Prompts: `prompts/video_landscape.md` +
  `prompts/video_query_generator.md`.
- **`VideoSpecAuthoring`** (`service/video_spec_authoring.py`) — the **deterministic
  commit gate**: diff guard → call `VideoQueryGenerator.generate` → call
  `VideoSpecService.save_version`. `commit(gym_id, criteria, *, source) →
  VideoSpecView | None`; returns `None` when criteria are unchanged. There is **no
  enqueue step** — the worker has no control surface to call. An `admin_update`
  version saved here is picked up by the worker's own timestamp derivation on its
  next tick (see `VideoService/CLAUDE.md`'s *Scheduling* section); a `feed_update`
  version (from `VideoFeedRefiner`, below) does **not** itself trigger a run — only
  `admin_update` versions count toward the worker's tier-1 trigger. The preset
  import (`src/presets/`) writes its own `system_update` version, which likewise
  triggers nothing.
- **`VideoFeedRefiner`** (`service/video_feed_refiner.py`) — **litellm** feed→criteria
  refine: `refine_from_feed`; loads unconsumed curation signals, calls the LLM, then
  delegates commit to **`VideoSpecAuthoring`** (not directly to `VideoSpecService`).

**`VideosService` (`service/videos_service.py`) is the domain FACADE** — it composes
`VideoFeedService`, `VideoSpecService`, `VideoSpecAuthoring`, and `VideoFeedRefiner`
(it does NOT inject `VideoQueryGenerator` directly; query gen is an internal of
`VideoSpecAuthoring`). Key methods: `load_latest_spec`, `save_accepted_spec` (→
`VideoSpecAuthoring.commit`), `refine_from_feed` (→ `VideoFeedRefiner`), plus all feed
operations (`load_feed_ids`, `load_pool_videos`, owner add/remove/keep). Template catalog reads
live in `PresetsTemplateService` (`src/presets/`); showcase (class/reward cards) lives in
`ThemeShowcaseService` (`src/theme/`). The router goes through the facade for all non-agent
video operations.

**The thin agent wrapper** lives in `service/video_agent/` (one file only):

- **`VideoAgentService`** (`service/video_agent/video_agent_service.py`) — exposes only
  `agent_turn(gym_id, request)`. Builds its Pydantic AI `Agent` internally with an
  explicit `AnthropicModel` from `settings.video_agent_model` (bare model name) and
  `settings.anthropic_api_key`. **No tools registered.** The agent converses to propose
  a `VideoSpecDraft` (criteria only), ask a multi-choice `AgentQuestion`, or reply with
  free text. Accept-path: `request.accepted_spec` → calls
  `videos_service.save_accepted_spec` → `VideoSpecAuthoring.commit`.

**One-way layering rule:** `VideoAgentService` → `VideosService` (facade) → the
general/regular services (`VideoSpecService`, `VideoQueryGenerator`, `VideoFeedRefiner`,
`VideoSpecAuthoring`). The regular services **never** call `VideoAgentService`.

**LLM split (Python 3.13):** litellm (`src/shared/litellm_client.py`,
`LiteLLMClient.complete_structured`) for `VideoQueryGenerator` and `VideoFeedRefiner`;
Pydantic AI (`pydantic-ai-slim[anthropic]`) for `VideoAgentService` only. Python 3.13
(`requires-python = ">=3.13,<3.14"`) — litellm cannot install on 3.14.

DI providers (videos domain, spec/agent + worker-status): `litellm_client`, `video_spec_service`,
`video_query_generator`, `videos_worker_status_service`, `video_spec_authoring`, `video_feed_refiner`,
`video_agent_service`, `videos_service` (facade). (The domain also wires the RAG read surface —
`member_video_profile_service`, `video_recs_service`, `video_search_service`, `video_feed_service` —
out of scope for this skill; see `FastApiBackend/CLAUDE.md`.)
DI providers (presets domain): `presets_service`, `presets_template_service`.
DI providers (theme domain): `theme_showcase_service`.
No `video_config_*`, `video_template_service`, or `video_showcase_service` providers remain.

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
| `admin_update` | the conversational agent accept-path | `POST /api/v1/gyms/{id}/video-agent` with `accepted_spec` in body → `VideosService.save_accepted_spec` → `VideoSpecAuthoring.commit` → `VideoSpecService.save_version` |
| `system_update` | the preset import | `PresetsService` → `presets_insert_spec_version.sql` (one versioned row, queries folded from the `video_gym` template) |
| `feed_update` | the feed-learning refiner | `VideoFeedRefiner.refine_from_feed` → `VideoSpecAuthoring.commit` → `VideoSpecService.save_version` |

All three write at **service_role** (clients never write the table; RLS revokes
INSERT/UPDATE/DELETE from `authenticated`). The agent path is gym-employee gated at
the app layer.

## 3. The conversational agent + the accept-path

- **Agent** (`service/video_agent/video_agent_service.py`, `VideoAgentService`):
  exposes only `agent_turn(gym_id, request: AgentTurnRequest)`. Builds a Pydantic AI
  `Agent` with `output_type=[str, SpecProposal, AgentQuestion]` — it returns **free
  text**, a **`SpecProposal`** (a short chat `message` **plus** a criteria-only
  `VideoSpecDraft` — no `queries` field — for the owner to review; the proposal is never
  silent, the `message` maps to `AgentTurnResponse.reply` and is appended to the chat), or
  a **multi-choice `AgentQuestion`** (`{question, options 2–6,
  multi_select}`) rendered as selectable chips in the CRM. **Zero tools registered.**
  The first turn seeds current-spec context by prepending it to the user message (plain
  service call — not a tool). System prompt: `prompts/video_agent_system.md`.

- **AgentQuestion.** When the agent needs to gather structured input (e.g. disciplines,
  intensity, style) it returns an `AgentQuestion` instead of free text. The CRM renders
  `options` as chip buttons; the owner's selection becomes the next turn's `message`.
  `multi_select=True` allows choosing multiple options.

- **Accept-path (deterministic, not LLM).** When the owner presses Accept, the CRM
  sends the confirmed `VideoSpecDraft` as `accepted_spec` in the next `AgentTurnRequest`
  to `POST .../video-agent`. The backend:
  1. Calls `VideosService.save_accepted_spec(gym_id, accepted_spec)` →
     `VideoSpecAuthoring.commit(gym_id, criteria, source="admin_update")`.
  2. `VideoSpecAuthoring.commit`: diff guard (returns `None` if criteria unchanged) →
     `VideoQueryGenerator.generate` (litellm two-call, produces queries) →
     `VideoSpecService.save_version` (appends the `admin_update` version — no enqueue;
     the worker's own timestamp derivation picks it up on its next tick).
  3. Runs the agent on a short "saved" outcome note so it can acknowledge and invite
     further changes. `AgentTurnResponse.saved = True`; the conversation stays open.

- **Query generator** (`service/video_query_generator.py`, `VideoQueryGenerator.generate`):
  **two litellm structured calls** — call 1 → `LandscapeResult` (channels / creators /
  series_events from the model's knowledge), call 2 → `QueriesResult` (criteria + that
  landscape → queries, ~⅓ name-targeted, spread across the genre clusters). Called by
  `VideoSpecAuthoring.commit` (the shared save path — the spread + landscape logic lives
  in one place). Prompts: `prompts/video_landscape.md`, `prompts/video_query_generator.md`.

- **Stateless conversation.** The server holds no session — each turn the client sends
  back the serialized `history` it got last turn (`ModelMessagesTypeAdapter`), and gets
  the new history to send next.

## 4. The feed→spec LEARNING LOOP (the core promise)

The spec *learns* from how the owner curates their feed. When an owner manually
rejects / un-rejects / re-adds a video in `gym_video_feed`, that action bumps
**`gym_video_feed.curated_at = now()`** (manual paths only — the automatic scan and
preset seed leave it NULL). Those are the learning signals.

`VideoFeedRefiner.refine_from_feed(gym_id, current)` (`service/video_feed_refiner.py`):

1. Loads the gym's **unconsumed** signals — feed rows where `curation_type = 'manual'`
   AND `curated_at > COALESCE(max(created_at) of the gym's last 'feed_update'
   version, '-infinity')` (`sql/video_feed_signals.sql`), joined to `video`
   for title/channel/description/transcript. Carries `scan_status` (keep vs reject),
   `curation_type` (always `'manual'` for signals), and `curation_reason` (the
   owner's optional free-text reason — unified across kept and rejected rows).
2. **No signals → returns `None`** (nothing new to learn; no version minted).
3. Otherwise renders the signals — each entry includes the video's title, channel,
   description snippet (≤400 chars), transcript snippet (≤600 chars, if stored),
   action label (`MANUALLY REJECTED` or `MANUALLY KEPT / UN-REJECTED`), and the
   owner's `curation_reason` (if any) — then feeds the current spec into
   `prompts/video_feed_refine.md` and runs a single structured Sonnet call →
   an improved **`VideoSpecDraft`** touching **both criteria AND queries**.
4. Calls `VideoSpecService.save_version` to append the result as a `feed_update` row.

The refiner is **batched**, not per-action (feed clicks stay instant; they only
record `curated_at`). Trigger: **pre-agent-view-open** — the CRM calls
`POST …/video-agent/refine-from-feed` right before the owner starts editing, so the
spec already reflects recent curation. The worker does **NOT** call the refiner: it
is a separate VideoService process and never reaches back into the backend
(cross-service). A refine that mints a `feed_update` version runs through
`VideoSpecAuthoring.commit`, which just saves it — a `feed_update` version is **not**
an `admin_update`, so minting it does NOT itself put the gym on the worker's tier-1
trigger. The gym still gets re-run on its own schedule regardless: the owner's manual
curation action that fed the refiner already bumped `gym_video_feed.curated_at`,
which is the worker's tier-2 trigger (once that curation settles for
`worker_curation_batch_hours`). So curation → tier-2-triggered feed regeneration
happens on the worker's own tick, independent of whether/when the refine runs; the
refine's only job is keeping the spec's criteria current for whenever the worker (or
the next agent session) reads it — the worker only ever *consumes* the spec (via
`gym_video_spec_latest`), never calling in.

## 5. Endpoints — all on the existing `videos_router` (gym-employee gated)

| Route | Purpose |
|---|---|
| `GET /api/v1/gyms/{id}/video-spec` | the gym's latest spec (`gym_video_spec_latest`); 404 if none yet |
| `POST /api/v1/gyms/{id}/video-agent` | one conversational turn **and** the accept-path. `body.accepted_spec` triggers the deterministic save via `VideoSpecAuthoring.commit`; `AgentTurnResponse.saved=True` + the agent acknowledges. Normal turns: `{message, history}` → `{reply?, draft?, question?, history, saved, usage?}` |
| `POST /api/v1/gyms/{id}/video-agent/refine-from-feed` | fold unconsumed curation → a `feed_update` version; 404 if no spec or nothing new |

`PUT /api/v1/gyms/{id}/video-spec` and `POST /api/v1/gyms/{id}/video-agent/generate-queries`
**do not exist** — accept is handled via `accepted_spec` in the POST body; query generation is an
internal step of `VideoSpecAuthoring.commit`, not a standalone route.

## 6. LLM stack — litellm for regular calls, Pydantic AI for the agent

**Python 3.13** (`requires-python = ">=3.13,<3.14"`). litellm cannot install on
Python 3.14 (uvloop/grpcio ABI), so the backend moved to 3.13 to get both frameworks.

### litellm — regular single-shot structured calls

`VideoQueryGenerator` and `VideoFeedRefiner` both use **`LiteLLMClient`**
(`src/shared/litellm_client.py`, `LiteLLMClient.complete_structured(prompt, schema,
model)`). The model string follows litellm's `provider/name` format (e.g.
`anthropic/claude-sonnet-4-6`); the `provider/` prefix selects which key to use from
`Settings`. Setting: `video_llm_model` (default `anthropic/claude-sonnet-4-6`). Keys:
`anthropic_api_key`, `openai_api_key`, `gemini_api_key`.

`LiteLLMClient` is a shared Singleton DI provider — it is NOT specific to the video
domain. Any future service that needs a one-shot structured LLM call should use it.

### Pydantic AI — the conversational agent only

`VideoAgentService` uses `pydantic-ai-slim[anthropic]`. It builds its `Agent` with an
explicit `AnthropicModel(model_name, provider=AnthropicProvider(api_key=…))` — the key
is passed directly from `Settings`, **not written to the environment**. There is no
`video_agent_llm.py` (that file was removed; all wiring is in `video_agent_service.py`).
Setting: `video_agent_model` (bare model name, default `claude-sonnet-4-6`).

`defer_model_check=True` is set on the agent so the backend boots even when no
`ANTHROPIC_API_KEY` is set — only the `/video-agent` endpoint fails (500) until the
key is in `FastApiBackend/.env`.

### Prompts

All prompts live in `src/videos/prompts/*.md` — `video_agent_system.md`,
`video_query_generator.md`, `video_feed_refine.md` — read at use, never inlined in
code (monorepo no-inline-prompt rule).

### Cost ledger

Agent/refiner token spend is surfaced in `AgentTurnResponse.usage` and logs; it is
**not** written to `video_cost_log` — even though the ledger's `video_execution_type`
enum now covers the worker's full stage set (`search | transcript | tag | enrich |
embed | scan`, each attributable to a `video_run_id`), none of those stages is
agent/refiner conversation, so there's no matching execution type to log it under.
A proper agent-cost ledger is deferred.

## 7. Testing without a key or a DB

For the **Pydantic AI agent**, use Pydantic AI test models (no key, no network):
`TestModel` auto-emits a valid output — by default the `str` reply path; use
`FunctionModel` (emitting a `SpecProposal` or `AgentQuestion`) to exercise the other
output branches. Override a built agent with `with agent.override(model=TestModel()):`.

For **litellm calls** (`VideoQueryGenerator`, `VideoFeedRefiner`), stub
`LiteLLMClient.complete_structured` directly (it's injected via DI) — no provider
key or network needed.

DB-touching reads/writes require the migration applied; pure unit tests for the
agent/generator/refiner logic use stubs. See `tests/videos/`.

## Key files (where the model actually lives)

- Schema (DB): `Database/supabase/schemas/gym_video_spec.sql` (table + `…_source`
  enum + `gym_video_spec_latest` view), `gym_video_feed.sql` (`curation_type NOT NULL
  DEFAULT 'automatic'` + `curation_reason TEXT` + `curated_at` — unified curation
  pair, `gym_video_curation_type` enum `automatic | manual`);
  `Database/python_data/schema/video.py` (`GymVideoSpecSource` mirror;
  `GymVideoCurationType` mirror for the `gym_video_curation_type` enum).
- Shared LLM client: `FastApiBackend/src/shared/litellm_client.py` (`LiteLLMClient`).
- Domain: `FastApiBackend/src/videos/` —
  - Router: `videos_router.py` (spec/agent routes: GET /video-spec, POST /video-agent,
    POST /video-agent/refine-from-feed)
  - Schemas: `schema/video_spec_schema.py` (VideoSpecView, VideoSpecDraft, QueriesResult),
    `schema/video_agent_schema.py` (AgentTurnRequest/Response, AgentQuestion)
  - Services (flat in `service/`): `video_spec_service.py` (VideoSpecService),
    `video_query_generator.py` (VideoQueryGenerator — litellm),
    `video_spec_authoring.py` (VideoSpecAuthoring — deterministic commit gate),
    `video_feed_refiner.py` (VideoFeedRefiner — litellm)
  - Agent wrapper (`service/video_agent/`): `video_agent_service.py` only
    (VideoAgentService — Pydantic AI; `video_agent_builder.py` and `video_agent_llm.py`
    were removed)
  - SQL: `sql/video_spec_load_latest.sql`, `sql/video_spec_insert_version.sql`,
    `sql/video_feed_signals.sql`
  - Prompts: `prompts/video_agent_system.md`, `prompts/video_query_generator.md`,
    `prompts/video_feed_refine.md`
- Writers elsewhere: `src/presets/service/presets_service.py` +
  `presets_insert_spec_version.sql` (`system_update`); feed `curated_at` + `curation_type`
  bumps in `src/videos/sql/{videos_reject_feed_video, videos_keep_feed_video,
  videos_insert_feed_video}.sql`. `videos_keep_feed_video.sql` writes
  `curation_type = 'manual', curation_reason = :accept_reason` (bind param name kept
  stable for CRM). `videos_insert_feed_video.sql` writes `curation_type = 'manual'`.
  `presets_insert_feed.sql` / `presets_insert_rejected_feed.sql` write
  `curation_type = 'automatic'`.
- DI: `src/core/dependencies.py` providers: `litellm_client`, `video_spec_service`,
  `video_query_generator`, `videos_worker_status_service`, `video_spec_authoring`,
  `video_feed_refiner`, `video_agent_service`, `videos_service`; settings in
  `src/core/config.py`: `video_llm_model` (litellm format), `video_agent_model`
  (bare model name), `video_query_count` (30), `video_agent_retries`,
  `anthropic_api_key`, `openai_api_key`, `gemini_api_key`.
- CRM consumer: `CRM/lib/features/video_agent/` (screen + Bloc + chat/draft/question
  widgets) and `CRM/lib/features/members/data/video_agent_repository.dart`; entry
  point in the settings screen. Calls `POST refine-from-feed` on open (brief loading
  state), runs the chat (chips for `AgentQuestion`), sends `accepted_spec` in the
  POST body when the owner presses Accept.

## This is a living document

When the spec model, the writers, the learning loop, the endpoints, the prompts, or
the Pydantic AI wiring change, update this skill **in the same change** — and keep
the lean `FastApiBackend/CLAUDE.md` `videos` spec/agent section in sync too. A
stale skill produces false "violation" findings in review and misleads the next
contributor.
