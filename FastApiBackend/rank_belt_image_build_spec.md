# Rank Belt Image Generation — Build Spec (Phase-2 handoff)

> **SUPERSEDED (2026-07-06) — kept as a possible future, not the current
> design.** The Rank System v2 rebuild rejected the generation-owned-image
> premise this whole spec is built on: `gym_ranks.image_url` is now a
> plain **user-writable field** (a preset default at ladder creation, with
> manual upload/override in the CRM edit page — same as any other image
> field), not a column the pipeline below exclusively writes. AI/
> ThemeService belt generation (this spec's `POST /ranks/generate` /
> `/ranks/regenerate`, the `RankImageSweep` reconciler step, the
> `image_gen` provenance column) is **deferred** — nothing here is built,
> and none of it reverses anything currently shipped. This doc is
> preserved as a possible future direction if/when generation gets
> prioritized again; do not treat anything below as the current design of
> `src/ranks/`. See `FastApiBackend/CLAUDE.md`'s "Ranks domain" section
> for how belt images actually work today.

**Status:** design locked 2026-07-02; build = Phase 2, its own branch/PR.
**Decision record:** the pivot doc in the docs vault —
`docs/Business/pivots/2026-07-02-20-rank-belt-images-theme-generated.md`.

**What this is.** The complete "what we need to do to make this work" for
theme-styled AI-generated rank belt images. This doc is the engineering
handoff so a cold session can build it. All file references were verified
against the repo on 2026-07-02 (rank-system branch + main).

**The flow in one paragraph.** A gym picks a theme (theme browser writes
`gyms.theme_design_id` directly via Supabase — the backend never sees the
change as a request). The backend **reconciler**, on its existing 2×-daily
cadence, diffs each rank's stored generation provenance against the gym's
current theme (+ the rank's current name/color); stale sets are regenerated
via a **new authenticated ThemeService generation API** (prompt authored
from the theme's brand brief + palette + rank name/color → `gpt-image-2` →
Recraft background removal → S3/CDN upload), and the backend writes
`image_url` + full provenance per rank in one transaction. Owners can
regenerate a single belt with feedback — but only when the set is current;
a pending set blocks manual regen with a clear CRM message.

---

## 1. DB (hand-write the migration; schema files first — `Database/CLAUDE.md` workflow)

- `gym_ranks` gains **`image_gen JSONB`** (nullable) — per-rank provenance,
  one column (lean-schema rule; precedent: `video.sql`'s tracing JSONB):
  `{theme_design_id, prompt, model, params: {size, quality, complexity},
  version, generated_at, feedback, inputs: {main_name, sub_name, color}}`.
- **Staleness rule (drives everything):** a rank's image is *stale* ⇔ the
  gym has a `theme_design_id` AND (`image_gen` IS NULL OR its
  `theme_design_id`/`inputs` differ from the gym's current theme + the
  rank's current name/color). Covers theme flips, brand-new ranks, AND
  renamed/recolored ranks (stale name/color baked into an image is wrong).
- `image_gen` joins `image_url` in the `GYM_RANKS` immutable frozenset
  (`Database/python_data/schema/immutable_columns.py`) — generation-owned,
  written only by the pipeline's own SQL.
- **Also fold into this migration:** `REVOKE UPDATE (current_rank_id)` on
  `members` for `authenticated` (access_rules) — the API side door was
  removed in Phase 1 (`MemberUpdateData`), but the per-column RLS grant
  from the "client-writable identity" set still allows a direct Supabase
  write that would bypass the `rank_changed` audit trail. Same-shape
  REVOKE for `gym_ranks.image_url`/`image_gen`/order columns if they carry
  authenticated UPDATE grants (check `access_rules/gym_ranks.sql`).
- Mirror updates: `schema_db_diagram.io`, `seed.mermaid` if the seed
  learns to stamp provenance (optional — seed may leave `image_gen` NULL
  so the sweep generates on first run, which also exercises the pipeline).

## 2. ThemeService — first authenticated generation endpoints on the deployed API

Facts (verified): the deployed API (`https://theme.combatden.net`, App
Runner, `ThemeService/src/api/`) is **read-only GET, no auth, CORS \*** —
generation is a local pipeline today. This build adds the first write
surface; that posture change must be documented in `ThemeService/CLAUDE.md`.

- **`POST /ranks/generate`** — body `{app_id, run_id, gym_id, ranks:
  [{rank_id, main_name, sub_name, color, order}]}` → for each rank:
  - Author the image prompt from the theme's brand brief + OKLCH palette
    + the rank's name/color. New prompt file
    `src/modules/images/prompts/rank_belt_prompt.md` (no inline prompts);
    reuse the existing "Achievement — a badge, medal, belt, or crest"
    treatment and the flat-solid-background-for-cutout rules from
    `image_prompt_rule.md`; assembly pattern =
    `image_node.py::_build_prompt` (`src/modules/images/image_node.py:185-244`).
  - Generate via `LiteLLMImageGenerator` (`src/shared/services/
    litellm_image_generator.py`, model `openai/gpt-image-2`; prompt author
    model constant lives beside `IMAGE_PROMPT_MODEL` in `image_node.py:70`).
  - Background: `BackgroundService` remove→crop (Recraft;
    `src/modules/images/background_service.py`).
  - Upload: new `rank_image_key()` beside `asset_urls.py:22` →
    `ranks/{gym_id}/{rank_id}.png` on bucket `combatden-assets` / CDN
    `cdn.combatden.net`, `?v=<sha256[:12]>` cache-bust (the `themes/`
    prefix was deliberately namespaced so the bucket could hold other
    classes — this is that case). Uploader: `src/core/asset_uploader.py`.
  - Return `{rank_id, image_url, prompt, model, params, version}` per
    rank. **Stateless** — never touches `apps/<app_id>/<run_id>/` run
    dirs (provenance persistence is the backend's job; the iron-clad
    never-hand-edit-a-run rule stays intact).
  - Bounded concurrency across the batch (~5, the single-slot image-regen
    concurrency convention).
- **`POST /ranks/regenerate`** — body `{app_id, run_id, gym_id, rank,
  feedback, current_image_url?}` → `edit_current_image` when an image
  exists (feedback → minimal edit instruction via `ImageEditService`,
  `src/modules/images/image_edit_service.py:43-72`), else create-new with
  feedback as the high-priority `USER_OVERRIDE` block (`OverwriteSpecs.specs`
  semantics, `schema/output/overwrite_specs.py:45-52`).
- **Auth required** (paid endpoints): shared static bearer token, config on
  both sides. Reject unauthenticated — an open generation endpoint is a
  cost-abuse hole.
- **Gap to close:** per-image metadata today records prompt + complexity +
  steering (`schema/output/image_output.py:12-34`) but **not model/params**
  — the endpoint response must include them (return-side only; no
  `output.yaml` change needed since nothing is written to run dirs).
- **Deployment:** App Runner env gains `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, `RECRAFT_API_KEY`, S3 write credentials, and the
  shared auth token. Re-run `make assets-finalize` only if response-header
  policies change (they shouldn't — same CDN).

## 3. FastApiBackend

- **Settings** (`src/core/config.py`, all as `Settings` fields):
  `theme_service_base_url`, `theme_service_api_key`, `theme_app_id` (the
  single hardcoded app id — referenced in `gyms.sql`'s comment but never
  actually created), `rank_image_sweep_enabled`.
- **Client:** a ThemeService client class modeled on `YouTubeMetadataClient`
  (`src/videos/service/youtube_metadata.py:71` — httpx per-call client,
  typed exceptions, Singleton DI). Generation calls need a generous
  timeout (60–300 s; image gen ≫ the default 30 s).
- **Reconciler sweep** — `RankImageSweep`, sixth sibling of the five in
  `src/reconciler/service/reconciler/` (constructor-injected into
  `ReconcilerService`, added to the `run()` list at
  `reconciler_service.py:70-74` + a DI Factory in
  `core/dependencies.py:757-792`):
  - Work-set SQL (new file in `reconciler/sql/`): stale ranks per §1's
    rule, grouped by gym, for gyms with a theme + a ladder.
  - Per gym: one batch `/ranks/generate` call → write `image_url` +
    `image_gen` for all its ranks in **one transaction**; per-gym failure
    isolation; return a `SweepResult` (name/processed/changed/skipped/
    errors — `src/shared/sweep_result.py`).
  - **Cadence = the existing 2×-daily cron** (`reconciler_cron_hours =
    [2, 14]` UTC). This IS the debounce: the reconciler has no per-item
    change tracking (re-derive + idempotent by design), so the provenance
    diff is the change detector, and the cadence caps spend — 20 theme
    flips/day → ≤2 regenerations.
- **Fast path:** preset import is the ONE backend-visible theme write
  (`presets_service.py` → `presets_set_theme.sql`). After it commits, kick
  the same per-gym generation fire-and-forget
  (`memberships_invoice_fetch_runner` strong-ref-set precedent) so a
  fresh onboarding demo gets styled belts immediately; the sweep stays
  the catch-all for theme-browser changes.
- **Manual regen endpoint:** `POST /api/v1/ranks/{rank_id}/regenerate-image`
  `{feedback}` — **409 when the rank is stale/pending** (the user is
  blocked from regenerating until reconciliation has run) or the gym has
  no theme. Otherwise run through the **tasks 202+poll** pattern
  (`src/tasks/` — new `TaskType.rank_image_regen`, handler implementing
  `TaskItemHandler.execute_item`; stale-task recovery via the existing
  `StaleTaskSweep` comes free). Completion writes `image_url` +
  `image_gen` (feedback recorded in provenance).
- **Read surface:** `RankResponse` gains `image_status`
  (`none | pending | current`, computed in `list_ranks.sql` against
  `gyms.theme_design_id` + the provenance) and surfaces the provenance
  fields (prompt/model/params/generated_at) — "return the prompt, model
  and everything that was used to create this rank."

## 4. CRM

- Render belt images: ladder rows (`rank_ladder_row.dart`) + the
  member-detail rank section, `Image.network` off the CDN URL with the
  existing color-swatch fallback when null/unloadable.
- **Pending banner** on the Ranks tab when any rank is `pending`: clear
  copy that belt images are being restyled to the new theme on the
  automatic cadence and that regeneration is unavailable until that
  completes; per-rank Regenerate buttons disabled in that state.
- **Regenerate** (enabled only when `current`): a feedback dialog — "what
  don't you like / what should change" — showing the current prompt for
  context; submits the 202 task, polls, row spinner, reload on
  completion.
- No-theme gym: no image surfaces at all (swatches only), regen hidden.

## 5. Cross-system docs (same change as the build)

Root `README.md` graph + `architecture.mermaid` gain the **FastApiBackend →
ThemeService** edge (new cross-system dependency; `mermaid-creation` skill
rules). FastApiBackend `README.md` + `architecture.mermaid` (new sweep,
client, routes). `ThemeService/CLAUDE.md` (generation surface, auth,
deployment env). `CRM/CLAUDE.md` (pending/regen UI). The vault pivot doc's
status changes only if the design materially changes (never edit it
retroactively otherwise).

## Verification plan

1. ThemeService: unit-test the prompt builder + key naming; one live
   generation smoke against a real theme (spend ~2 images).
2. Backend: sweep unit tests (mocked client — staleness set, per-gym
   isolation, transaction write); regenerate endpoint 409-when-pending;
   integration: seed a gym with a theme + NULL provenance → run the sweep
   once → every rank has `image_url` + `image_gen`; flip the theme id in
   the DB → sweep regenerates; rename a rank → only that rank regenerates.
3. CRM: analyze + widget states (pending banner, disabled regen, fallback
   swatch); qa-crm live pass on the Ranks tab + member detail.
4. Cost check: assert the sweep's work-set query returns empty on a
   second consecutive run (idempotence = no double spend).

## Open questions (settle before/while building)

- Belt image size/aspect for the CRM ladder + member app surfaces (the
  engine emits 1024×1024 with background removed; may want a wide belt
  crop treatment in the prompt instead).
- Whether the seed should stamp synthetic provenance (no generation cost,
  demo-ready images?) or leave NULL and let the sweep generate real ones
  for the demo gym (real spend, real pipeline exercise).
- `rank_presets.image_url` stock art: keep as pre-generation placeholder
  or drop entirely once generation lands.
