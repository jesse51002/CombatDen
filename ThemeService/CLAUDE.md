# AICustomizationPipeline — Coding Standards

Python/Pydantic package. See `README.md` for what it does.

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

This file is a living document — exactly like a skill (above), it must track reality. Whenever the pipeline code genuinely diverges from what this CLAUDE.md says (a removed module, a renamed system, a changed schema, a rule the code has outgrown on purpose, an architecture change), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

---

## Iron-clad rule: never hand-edit a produced run

A run directory's **produced artifacts** — `output.yaml`, `expansion_cost.yaml`,
and the files under `final_images/` / `images/` / `icons/` — are **never edited
by hand**. To change anything in an existing run you use the scripts:
`scripts/expand` (fill not-yet-done slots), `scripts/regen` (re-make
colour/font/text/icon slots), `scripts/regen_image` (images),
`scripts/edit_customization` (a validated, targeted edit of the brief
`customization.yaml`), or a full pipeline run (`src/cli.py`). The brief is the
one editable *input* — and even it goes through `edit_customization` (which
re-validates), not raw text munging; `app.yaml` is architect-owned.

If a change someone wants **cannot** be expressed through those scripts, do NOT
work around it by editing an artifact — say so plainly and surface it as a
feature to add to the pipeline. A missing capability is a feature request,
never a manual edit.

---

## Core principle: app-agnostic

Nothing app-specific lives in Python code. App-specific configuration
(slot inventories, descriptions, ids, names) lives in `apps/<app_id>/`
YAML files only. Adding a new app must be a YAML-only change.

If you find yourself adding a constant, enum, or class branch that
only makes sense for one app, push back — it belongs in YAML.

---

## Sibling repos

- `../MobileApp/` — Flutter app that consumes the pipeline output.
- `../FastApiBackend/` — its `CLAUDE.md` carries the broader Python
  conventions for this monorepo (imports, enums, type hints, async,
  error handling). Apply those here unless this file overrides.

---

## Python standards

- **Pydantic v2.** Every model sets `ConfigDict(extra="forbid")` so
  YAML typos fail loudly. The sole deliberate exception is the
  output-read models — `Output` (`schema/output/output.py`),
  `ImageOutput` (`schema/output/image_output.py`), and the two output
  group wrappers `ColorPalette` (`schema/output/color_palette.py`) and
  `ImageSet` (`schema/output/image_set.py`): those use `extra="ignore"`
  so an externally- or previously-produced `output.yaml` carrying
  since-removed keys still validates (the stale keys are dropped, not
  rejected). Input contracts (`app.yaml`, `customization.yaml`, slots,
  etc.) keep `forbid`.
- **One concept per file.** Each Pydantic class lives in its own file
  under `schema/` unless several classes form one tight unit.
- **Helpers belong to their class.** A function used only by one class
  is a `@staticmethod`/method on that class, not a module-level function
  sitting above it. Module level is reserved for genuinely shared
  helpers and the `UPPER_CASE` constants (including names other modules
  or tests import).
- **Native generics** (`list[X]`, `dict[str, Y]`), pipe unions
  (`X | None`), type hints on every parameter and return.
- **Absolute imports** from `schema.*`. No relative imports.
- **Constants in `UPPER_CASE`** at the top of the file. No magic
  strings or regexes mid-function.

---

## No inline prompts or SQL

- **Never inline an LLM/agent prompt in Python.** Every prompt lives in
  its own `.md` file (e.g. `modules/prompts/<name>.md`) and is read at
  use. Python may hold the *path* constant, never the prompt text.
- **Never inline SQL in code.** Every query lives in its own `.sql`
  file and is read at use. (No SQL in this package today — the rule
  stands for when there is.)
- Rationale: prompts and queries are reviewed, diffed, and tuned on
  their own; burying them in string literals hides them and invites
  ad-hoc edits mid-function.

---

## Async everywhere

Every service and module method is `async`. The pipeline core is provider- and
transport-agnostic and is expected to move behind a FastAPI app later; the CLI
is just one entrypoint over the async core. Do not introduce blocking I/O — use
async clients (`litellm.acompletion` / `litellm.aimage_generation`) and
`await` everything. Keep modules independently awaitable so they
can be gathered concurrently later without a refactor.

---

## Atomic modules

A module's public method is the smallest indivisible unit of work, not a
batch. The colour module resolves the whole palette in one call; the image
module resolves **one** image (`run(slot, palette) -> ImageOutput`).

Modules never loop the app's slot inventory, build aggregate result
models, or touch threading/concurrency — the **executor** owns iteration
and is the only place parallelism may later be added (a bounded gather),
with zero module changes. A module that loops slots or returns a
"set of everything" is the smell; push that loop up into the executor.

### A module's `run()` returns its full output

Each module returns its **complete, self-contained output exactly as it
lands in `output.yaml`** — never a partial, a diff, a delta, or a handle
to fetch the rest. The node-return-type ⇄ output-group mapping is 1:1:
`ColorNode → ColorPalette` (= `color_set`), `FontNode → FontSet`
(= `font_set`), `ImageNode → ImageOutput` (= `image_set.images[id]`),
and so on.

**Why this is a hard invariant, not a style note:** the `expand` flow
(`scripts/expand/run.py`, `src/executor/seed.py`) reconstructs the
executor's start-state by validating each saved `output.yaml` group
straight back into the model its node returns, then seeds the DAG with the
done nodes and runs only what's missing. A module that returned less than
its full output couldn't be seeded from a saved run — it would force a
re-run (and re-spend) of work already done. Keep every new module
round-trippable this way: whatever `run()` returns must be everything
needed to reconstruct that node as done, with no side channel.

---

## Typed primitives

`schema/primitives.py` is where shared string-shaped types live —
`RootModel[str]` wrappers that validate on construction and serialize
back to plain strings in YAML.

When a new string-shaped concept needs validation, add it here as
another `RootModel[str]` and reuse it across schemas. Don't repeat
the same regex check across multiple field validators when one
primitive captures it.

---

## Output groups

Each group on the produced `output.yaml` is its own Pydantic model under
`schema/output/`, never a bare `dict`/collection on `Output`. The group
is exposed on `Output` under a `*_set` field/YAML key (`color_set` →
`ColorPalette`, `image_set` → `ImageSet`) with the inner collection
keeping its plain plural name, so the artifact reads `color_set.colors`
/ `image_set.images`, never the redundant `colors.colors`.

These wrappers exist so a group can gain run-wide fields (e.g.
`ColorPalette.mode`) without another breaking `output.yaml` reshape;
that is why they are read back with `extra="ignore"` like `Output` /
`ImageOutput`. A *required* field on a group stays required — adding one
is a deliberate breaking change that requires migrating every existing
`apps/<app>/*/output.yaml` (and the `tests/data/` fixtures).

---

## Dependencies

Poetry, with an in-project `.venv` (`poetry.toml`: `in-project = true`).
Add dependencies with `poetry add <pkg>` (dev: `poetry add --group dev
<pkg>`) — **never hand-edit `pyproject.toml` or `poetry.lock`**; let
Poetry resolve and write the lock. Run all code, scripts, and tests via
**`poetry run`** (`poetry run python ...`, `poetry run pytest`), never a
bare `python3` or the raw `.venv/bin/*` entrypoints. `poetry run` resolves
the project venv itself, so it sidesteps the stale hardcoded-shebang
breakage the `.venv/bin/*` scripts hit when this package was renamed.

---

## Production deployment (read-only API)

The read-only API (`src/api/main.py`, `make api`, port 8000) ships to **AWS App
Runner** as a Docker image at `https://theme.combatden.net`. See
`../DEPLOYMENT.md` for the full runbook (ARNs, DNS, redeploy, pause/resume).

- **Images/icons are served from S3 + CloudFront (`cdn.combatden.net`), not the
  container.** The image no longer bakes the ~2.6 GB of bytes — only the per-run
  `output.yaml` metadata is copied (`.dockerignore` excludes
  `apps/**/{images,final_images,icons}/`; `COPY apps/` then brings just the
  yaml). `ASSETS_CDN_BASE_URL` **defaults to the prod CDN in code**
  (`src/api/config.py`), so the API always emits absolute CDN URLs and the byte
  endpoints 307-redirect there — no App Runner env var required (a relative path
  would 404 now that the bytes are de-baked). Set it empty to serve relative
  paths + local files in the dev loop. See `src/core/asset_urls.py` +
  `src/api/schema/output_response.py`.
- Cache-busting stays `?v=<content-hash>` (already stamped by the Writer);
  CloudFront is configured to include `v` in the cache key, so a regenerated
  asset busts the CDN with no invalidation. **Never serve via the CDN without
  that cache-policy setting** (see `../DEPLOYMENT.md`) or regenerated images go stale.
- **CORS is mandatory on the CDN.** The clients are Flutter **web** apps; their
  CanvasKit renderer fetches each image via XHR and decodes it, which the browser
  blocks cross-origin unless the response carries `Access-Control-Allow-Origin`.
  The bytes are on `cdn.combatden.net`, a different origin than the apps, so
  without the CORS header every image is a broken placeholder *despite* a 200.
  `deploy-assets/finalize.py` attaches a response-headers policy (`*`) at the
  edge; re-running `make assets-finalize` patches a live distribution. This is
  inherent to cross-origin images in Flutter web — not a CloudFront quirk.
- **Bytes → S3:** `make sync-assets` (`scripts/sync_assets/`) mirrors every
  `final_images/` + `icons/` file to the bucket (backfill + repair, skips
  unchanged). New runs self-upload from the `Writer` when `ASSET_UPLOAD_ENABLED=1`
  (opt-in; off locally) — see `src/core/asset_uploader.py`. boto3 is an
  upload-only dep, imported lazily so the read path/tests don't need it.
- Runtime env (App Runner vars, never baked): `GOOGLE_FONTS_API_KEY` (required,
  font delivery). `ASSETS_CDN_BASE_URL` is **optional** — it defaults to the prod
  CDN in code, so prod works without it; only set it to target a different CDN
  (or empty for local serving). `CORS_ORIGINS` optional.
- `make docker-build` / `make ecr-push` build + push + trigger a redeploy;
  `make pause` / `make resume` toggle the demo (App Runner Pause/Resume).
- Only the **read path** is containerized. The pipeline (`src/cli.py`, scripts,
  `make sync-assets`) is not — it stays a local tool.

---

## Tests

Run the suite with `make test`.

Round-trip every example under `apps/<app_id>/` against its matching
Pydantic model before committing (covered by `tests/test_pipeline.py`).

---

## What NOT to do

- Do not hardcode app-specific names, ids, or descriptions in Python.
  Anything specific to one app belongs in `apps/<app_id>/` YAML.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not import from `../FastApiBackend/` or `../Database/`. This
  package is shape-only; it doesn't share types with the delivery side.
