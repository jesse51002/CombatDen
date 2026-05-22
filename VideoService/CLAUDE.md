# CustomYoutubeService — Coding Standards

Python/Pydantic package. See `README.md` for what it does.

> **Temporary by design.** This is a lightweight, standalone service kept
> separate for speed. The `videos_config.yaml` contract and its Pydantic models
> are expected to fold into `../FastApiBackend/` later. Keep the surface small
> and the schema clean so that migration is a lift-and-shift, not a rewrite.
> Executing the searches against the YouTube Data API lives in the **manual
> batch script** `scripts/youtube_batch/` (run with `make youtube APP_ID=<id>`),
> kept out of `src/api/` and `schema/` so the read-path and contract stay
> query-free. Curating the fetched feed (removing anti-gym / `avoid_desc`
> videos) is the **`audit-output` skill** (`/audit-output`), backed by the
> context-lean `scripts/youtube_batch/audit.py` `list` / `remove` commands.

---

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the
user's explicit response. Never assume, recommend-and-proceed, or defer the
choice unilaterally. Presenting researched options is encouraged; making the
choice for the user is not.

---

## Core principle: company-agnostic

Nothing company-specific lives in Python code. Each company's brief (its name,
niche, video descriptions, and search prompts) lives in `apps/<app_id>/
videos_config.yaml` only. Adding a new company must be a YAML-only change.

If you find yourself adding a constant, enum value, or class branch that only
makes sense for one company, push back — it belongs in YAML. The one exception
is the `VideoType` enum: it is the fixed, shared genre vocabulary every brief
draws from, not a per-company value.

---

## Sibling repos

- `../FastApiBackend/` — its `CLAUDE.md` carries the broader Python conventions
  for this monorepo (imports, enums, type hints, async, error handling). Apply
  those here unless this file overrides. The schema here will eventually migrate
  into it.
- `../CustomizationService/` — this service is modelled on its `brand-brief`
  skill + read-only `src/api`. Mirror its patterns when extending.

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

Run the suite with `make test`. Round-trip every example under `apps/<app_id>/`
against the `VideosConfig` Pydantic model before committing.

---

## What NOT to do

- Do not hardcode company-specific names, niches, or search prompts in Python.
  Anything specific to one company belongs in `apps/<app_id>/videos_config.yaml`.
- Do not add `dict[str, Any]` escape hatches to dodge strict typing.
- Do not add YouTube Data API calls to `src/api/` or `schema/` — querying lives
  only in the `scripts/youtube_batch/` batch script, so the read-path and
  contract stay query-free.
