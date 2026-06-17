# Monorepo Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills

All skills live in one place: `.claude/skills/` at the codebase root. This is the single, centralized place to look — skills for every subsystem (FastApi backend, CRM, services, data models) live here together, not scattered in per-system `.claude/` folders. Before starting any task, check this directory for a relevant skill and use it.

**Do not list the skills in this file.** Reading `.claude/skills/` yourself is the job — a hardcoded list here would drift out of date the moment a skill is added or renamed. Check the directory, don't trust a copy of it.

**When to create a skill** — a skill must capture something **specific**, never a general overview of a whole system. Create one when either is true:
- A specific complex piece of a subsystem — a particular data model, mechanism, or workflow (e.g. the discount snapshot model, the QA-the-pages flow) is involved enough to need more guidance than a lean CLAUDE.md should carry.
- There's a specific how-to that isn't covered in any CLAUDE.md and is too detailed to add without cluttering it. CLAUDE.md stays lean (how to work here); deep or specific knowledge becomes a skill.

**Never make a general "FastApi skill" or "CRM skill"** *as documentation*. A whole-system skill that just *describes* a system would copy that system's CLAUDE.md and add nothing — a knowledge/instruction skill has to be about one specific complex thing or one specific procedure. The two existing knowledge skills are the model: `qa-crm` is a concrete QA-the-pages workflow and `discounts-guide` is one complex data model — neither is "the CRM" in general.

**Exception — skills that *are* the system's functionality.** Some skills aren't instructions at all: they're operational agents that run an engine — e.g. ThemeService and VideoService have skills that scrape, scan, generate a theme, or produce a video brief. These are part of the subsystem's functionality, not a description of it, so the "no general system skill" rule does not apply to them. The test: does the skill *do* something the system needs done (an executable capability/agent), or does it just *explain* the system (which duplicates the CLAUDE.md)? The former is always fine, even when it's "for the whole system"; only the latter is banned. (The root System map already frames these as "the skills/scripts that operate each engine.")

Per *No assumptions*, propose the skill and wait for confirmation before creating it.

**Naming** — short and descriptive, kebab-case, 2–3 words max. Specific enough to tell skills apart, never generic: `qa-crm` (not `qa`), `discounts-guide`. The two existing skills, `.claude/skills/qa-crm/` and `.claude/skills/discounts-guide/`, are the model to follow.

**Describe what it IS, not what was dropped.** A skill (and any doc) states how the system works *now* — never a changelog of what was removed or how it used to work. Don't narrate deletions ("X was deleted", "previously stored Y", "the old design"). The one exception: mention a removed/rejected approach only when it's a load-bearing **"what we want / don't want" example** that explains why the current design is shaped this way (e.g. "the thing we never want here: a cross-member recalculation"). Otherwise, cut it.

## Skills are living documents
When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them. This applies to every system's skills.

## CLAUDE.md is a living document

Every CLAUDE.md in this repo is a living document — exactly like a skill, it must track reality. Whenever code genuinely diverges from what a CLAUDE.md says (a new live backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, an architecture change), **update that CLAUDE.md in the same change** so the doc and the code never drift apart. Never leave one stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## System map — keep README.md and architecture.mermaid current
- The root `README.md` holds the **high-level** system graph (the systems and how they connect); `architecture.mermaid` holds the **full detailed** graph (every system's inner nodes, the ThemeService/VideoService API-vs-creation split, and the skills/scripts that operate each engine).
- Both are living documents. Whenever the architecture changes — a new system, a new or removed cross-system dependency, a renamed service, a new external service, an API/creation change, a new skill or script on an engine — **update both the README high-level graph and `architecture.mermaid` in the same change** so neither drifts from reality.
- Author/edit both graphs with the `mermaid-creation` skill and follow its rules (top-down `TB`, sibling-only edges, the fixed color palette, render + `check_siblings.py` validation). Don't hand-edit a graph in a way that breaks those rules.

## Editing the Claude review workflows (`.github/workflows/claude*.yml`)
- `claude-code-review.yml` (auto PR review) and `claude.yml` (the `@claude` assistant) run `claude-code-action`, whose GitHub App token exchange requires the workflow file on a PR branch to be **byte-identical to the version on `main`**. If a feature branch edits one of them, every review run on that branch dies at startup with `App token exchange failed: 401 Unauthorized — Workflow validation failed`.
- So any change to these files must land on `main` FIRST, via a small dedicated PR, then be synced onto the feature branch — **never edit them on a feature branch alone.** This bites often; treat it as a hard rule. (Even the dedicated PR's own review run will 401, because that PR is the one changing the file — that's expected, ignore it; the merge still works.)

## No inline prompts or SQL
- Never inline an LLM/agent prompt in code. Every prompt lives in its own `.md` file and is read at use; code may hold the path, never the prompt text.
- Never inline SQL in code. Every query lives in its own `.sql` file and is read at use.
- This holds repo-wide and for every system, including ones not using prompts or SQL yet.

## Organization
- Each system (backend, frontend, database, etc.) lives in its own top-level directory.
- The root directory must stay clean: no application code, no config files for individual systems.
- Each system directory has its own CLAUDE.md with system-specific coding standards.
- Always read the local CLAUDE.md for the subfolder/system you're working in before doing work there, and follow it in addition to the root and codebase-level rules.
- Template CLAUDE.md files for common system types are in `claudes/` — copy and customize for each new system.

## Adding a New System
- Create a new top-level directory with a clear, descriptive name (e.g., `Backend/`, `WebApp/`, `MobileApp/`, `Database/`).
- Add a CLAUDE.md inside it. Start from the relevant template in `claudes/` and customize for the project.
- If the new system shares data contracts or code with other systems, document the cross-references in both CLAUDE.md files.

## Cross-System References
- When one system depends on artifacts from another (e.g., backend reads schema definitions from Database/, frontend uses an OpenAPI spec from Backend/), document the dependency path in the consuming system's CLAUDE.md.
- Use relative paths from the system directory (e.g., `../Database/schemas/`).

## Worktrees
- When creating a git worktree, branch off the **local** branch (e.g. local `main`), NOT the remote (`origin/main`). The remote often lags behind local, so a worktree branched from it silently misses recent work.
- If a worktree was created from the remote, run `git reset --hard main` in it before starting (safe while its branch has no commits), and verify expected recent files exist before building.
- **A fresh worktree has NO env files — copy them in before running or testing anything.** Per-system secret env files are gitignored, so a clean worktree checkout won't contain them; every system (and its tests/seed) will fail or warn until they're present. Copy each from the **root codebase checkout** into the worktree at the **same relative path**. The set to copy: `FastApiBackend/.env`, `CRM/.env.dev`, `CRM/.env.prod`, `Database/python_data/.env`, `VideoService/.env`, `VideoService/.env.prod`, `ThemeService/.env`. They stay gitignored, so the copies are never committed (verify with `git check-ignore`). Re-copy if the root's secrets are later regenerated. (`FastApiBackend/.venv` is symlinked separately by the FastApiBackend worktree setup — see the `fastapi-worktree-setup` note.)

## Meld diff review (root Makefile)
**Always run meld at a review gate.** Whenever you present completed work — or a piece of a multi-step change — for my review, proactively launch `make meld` so I can see the diff visually; don't wait to be asked. This is the default for every "here's what I did, please review" hand-off, not only when I explicitly say "open a diff".

When asked to spin up a diff / open a review of the current checkout (e.g. a worktree under `.claude/worktrees/`), use the root Makefile targets:
- `make meld` — meld directory diff of the current working tree against the **root codebase checkout's** HEAD. Works from inside any worktree (resolves the root via `git rev-parse --git-common-dir`).
- `make meld-origin` — same, but fetches and diffs against `origin/main`.
- `make meld-branch` — same, but fetches and diffs against the CURRENT branch's remote version (`origin/<branch>`) — i.e. everything local that origin doesn't have yet.
- `make setup-meld` — one-time machine setup (Flatpak meld + global git difftool config). Only needed if meld isn't installed.
- **Always run these in the background** (`run_in_background: true`) — the command blocks until the user closes the meld window; running it in the foreground stalls the session.
- **Untracked files are invisible to git diff** — git only diffs tracked content. Every meld target therefore depends on `make meld-intent`, which `git add -N`s (intent-to-add: path registered, NO content staged) all untracked files so they appear as new-vs-empty in the diff — **excluding `.claude/worktrees/` checkouts and `.venv` symlinks** (never to be committed).
- The diff is a launch-time snapshot of *which files differ* — auto-update is partial:
  - **Edits to files already in the diff flow through live.** The right pane is symlinks to the real working-tree files, so further edits to those files show on refresh (Ctrl+R in meld) — no restart.
  - **Files created/deleted/clean-at-launch do NOT appear** (and a file created AFTER launch isn't intent-added yet). git stages only the files that differed at launch; refreshing can't surface anything else. Close meld and rerun the target.
  - Practical rhythm while an agent works in a worktree: refresh while it iterates on the same files; close-and-rerun once it has touched new ones.
- **The meld targets restart on their own — just run `make meld` (in the background); no separate kill step.** Every meld target depends on a `kill-meld` prerequisite that runs `flatpak kill org.gnome.meld` first, so a window left open from a prior run is always closed before the new diff opens. (Why it matters: a second launch into an already-open window hands off to it and exits, git then deletes the difftool staging dirs, and the new window shows empty — so restarting is mandatory, and now automatic.)
- **Do NOT add your own `pkill -f meld` kill before/around `make meld`.** It matches the *full command line*, so it also matches the very bash invocation containing `make meld` and kills the launcher mid-run (the old failure mode: exit 144, no window). The Makefile deliberately uses `flatpak kill org.gnome.meld` (the app id), which can never match the launcher. If meld ever isn't the Flatpak build, fix the `kill-meld` target — don't reintroduce a `pkill -f` at the call site.
- **Default workflow/sub-agents to Sonnet with 1M context** (`model: 'sonnet[1m]'` on `agent()` calls / subagent launches, or the phase/run model override; plain `'sonnet'` only where the harness rejects the `[1m]` variant) unless a task genuinely needs Opus-level reasoning. Workflows fan out many agents at once; running them on Opus is far more expensive and **hits rate limits** fast (a 75-agent Opus fan-out got rate-limited mid-run). Sonnet has higher throughput and lower cost, and the 1M-context variant keeps large rename/review/data passes from compacting mid-task — the right default for fan-out work like data passes, conversions, broad reviews, and per-file edits. Reserve Opus for the few agents that actually need deep reasoning.
- Keep concurrent fan-out reasonable; prefer Sonnet + batching over a huge Opus burst.

## Calling the FastApi Backend
- The authoritative request/response contract is the backend's Pydantic schemas in `FastApiBackend/src/<domain>/<domain>_schema.py`. Before writing or modifying any code that calls a backend endpoint (seed scripts, tests, other services), read the matching schema there and include every field listed under `required`.
- `Database/openapi.json` is an **optional, gitignored** local convenience dump. It is never committed, never expected to exist, and must never be flagged as missing or stale. To regenerate it locally from a running backend: `curl localhost:8000/openapi.json > Database/openapi.json`.
