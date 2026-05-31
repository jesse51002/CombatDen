# VideoService — Coding Standards

Python/Pydantic package. See `README.md` for what it does. (Formerly
CustomYoutubeService — renamed when the scope expanded beyond YouTube.)

> **Standalone by design.** This service owns the full gym-video lifecycle:
> gym config authoring, video pool scraping + classification, feed scanning, and
> a read-only API consumed by other systems. The Pydantic schema and models may
> eventually fold into `../FastApiBackend/`; keep the surface small and the
> schema clean so that migration stays a lift-and-shift. All data-fetching and
> scoring lives in `scripts/` — the read path in `src/api/` and `schema/`
> stays query-free.

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

Nothing gym-specific lives in Python code. Each gym's config (its
disciplines / `gym_type`, chosen ThemeService design id, video specification,
search queries, scan-curated feed of good/rejected video ids + scan costs, and
optional classes + rewards) lives in `gyms/<gym_id>.yaml` only. The shared
video pool lives flat in `videos/`, and spend is logged to `cost_log.yaml`.
Adding a new gym must be a YAML-only change.

If you find yourself adding a constant, enum value, or class branch that only
makes sense for one gym, push back — it belongs in YAML. The one exception is
the `VideoType` enum: it is the fixed, shared genre vocabulary every gym draws
from, not a per-gym value.

---

## Sibling repos

- `../FastApiBackend/` — its `CLAUDE.md` carries the broader Python conventions
  for this monorepo (imports, enums, type hints, async, error handling). Apply
  those here unless this file overrides. The schema here will eventually migrate
  into it.
- `../ThemeService/` — this service is modelled on its `brand-brief` skill +
  read-only `src/api`. Mirror its patterns when extending. Each gym's YAML
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
- **Absolute imports** from `schema.*` / `src.*`. No relative imports.
- **Constants in `UPPER_CASE`** at the top of the file. No magic strings or
  regexes mid-function.

---

## No inline prompts or SQL

- **Never inline an LLM/agent prompt in Python.** Every prompt lives in its own
  `.md` file and is read at use. Python may hold the *path* constant, never the
  prompt text. (The interview lives entirely in the `video-brief` skill's
  `.md` files; there is no LLM call in the API today — the rule stands for when
  there is.)
- **Never inline SQL in code.** Every query lives in its own `.sql` file and is
  read at use.

---

## Async everywhere

Every service method is `async`, matching the monorepo's FastAPI convention, so
the read path can later gain real I/O (or move behind `FastApiBackend`) without
a refactor. Do not introduce blocking I/O on a hot path.

---

## Dependencies

Poetry, with an in-project `.venv` (`poetry.toml`: `in-project = true`). Add
dependencies with `poetry add <pkg>` (dev: `poetry add --group dev <pkg>`) —
never hand-edit `pyproject.toml` or `poetry.lock`. Run all code, scripts, and
tests via **`poetry run`** (`poetry run uvicorn ...`, `poetry run pytest`),
never a bare `python3` or the raw `.venv/bin/*` entrypoints.

---

## Tests

Run the suite with `make test`. Round-trip every example under `gyms/` against
the `Gym` Pydantic model before committing (`make gym-check GYM_ID=all` also
validates schema + enum + filename consistency).

---

## What NOT to do

- Do not hardcode gym-specific names, disciplines, or search prompts in Python.
  Anything specific to one gym belongs in `gyms/<gym_id>.yaml`.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not add scraping or scoring calls to `src/api/` or `schema/` — fetching
  lives in `scripts/scraper/`, scanning in `scripts/scan/`, so the read-path
  and contract stay query-free.

---

## Three jobs / workflow

The service has exactly three jobs, each backed by its own `scripts/` module
and `make` target:

1. **Make/edit a gym** (`make gym-check GYM_ID=<id>`) — author or update a gym
   file at `gyms/<gym_id>.yaml`, then validate it round-trips the `Gym` schema.
   This is a YAML-only change; no code touch needed.

2. **Scrape + classify** (`make scrape [GYM_ID=<id>]`) — gather the gyms'
   search queries, fetch videos via Apify (`scripts/scraper/`), write the shared
   pool to `videos/` (flat, one YAML per video id), then tag every pooled video
   with genre + gym_type labels. Appends `SEARCH` + `TAG` entries to
   `cost_log.yaml`.

3. **Scan** (`make scan GYM_ID=<id|all>`) — run the per-gym keep/drop scan
   against the gym's specification (`scripts/scan/`), overwriting its
   `good_video_ids` / `rejected_video_ids` and appending a `ScanCost` to its
   history. Appends a `SCAN` entry to `cost_log.yaml`.

---

## Read-only API (`src/api/`)

Gym-id-keyed, read-only. Run with `make api` (port 8002).

- `GET /gyms` — list all gym ids.
- `GET /gyms/{gym_id}` — full `GymDetail` (spec, classes, rewards). The mobile
  app loads this once at startup.
- `GET /gyms/{gym_id}/videos` — paginated curated feed.
- `GET /gyms/{gym_id}/videos/preview` — one-shot "All" preview (a few videos
  per genre). `?rejected=true` previews the scan's rejected list instead.
- **Channel-avatar backfill (both feed endpoints).** The scraped pool has no
  channel avatars — Apify never returned them, so every pooled
  `channel_avatar_url` is empty. At serve time, an empty avatar is filled with
  one of the gym's own instructor headshots (`gym.classes[].instructor_image_url`),
  picked deterministically per video (so it never flickers / stays cacheable). A
  real avatar, or a gym with no classes, is left untouched. Pure read-path
  transform — no data/schema change. See `src/api/service/avatar_fallback.py`.
- `/viewer` — internal dev-only HTML viewer (served by `viewer_router.py`);
  never expose publicly. ⚠️ **Known gap on the demo deployment:** the App Runner
  image includes `viewer_router`, so `/viewer` is currently reachable at
  `https://video.combatden.net/viewer` (read-only, but it serves the rejected
  list too). Gating/removing it for prod is a pending user decision — see
  `../DEPLOYMENT.md`.

---

## Production deployment (read-only API)

The read-only API (`src/api/main.py`, `make api`, port 8002) ships to **AWS App
Runner** as a Docker image at `https://video.combatden.net`. See
`../DEPLOYMENT.md` for the full runbook (ARNs, DNS, redeploy, pause/resume).

- `Dockerfile` + `.dockerignore` build a `python:3.13-slim` image that **bakes in
  the served `gyms/` + `videos/` data** (~300 MB — not in git). Pipeline dirs
  (`scripts/`, `tests/`) are excluded; only `src/`, `schema/`, `gyms/`,
  `videos/`, and `cost_log.yaml` are copied. `config.py` resolves `data_root` to
  `<root>`, so the layout is unchanged inside the container.
- No runtime secrets (the read path is disk-only).
- `make docker-build` / `make ecr-push` build + push + trigger a redeploy;
  `make pause` / `make resume` toggle the demo (App Runner Pause/Resume).
- Only the **read path** is containerized; the scrape/scan scripts stay local.
