# AICustomizationPipeline — Coding Standards

Python/Pydantic package. See `README.md` for what it does.

---

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the
user's explicit response. Never assume, recommend-and-proceed, or defer the
choice unilaterally. Presenting researched options is encouraged; making the
choice for the user is not.

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
  YAML typos fail loudly.
- **One concept per file.** Each Pydantic class lives in its own file
  under `schema/` unless several classes form one tight unit.
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
