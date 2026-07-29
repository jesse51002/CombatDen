# Monorepo Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Don't silently inherit existing problems

When you find a bug, anti-pattern, wrong behavior, or stale rule that **already exists** in the codebase — a pre-existing gap, a flawed pattern other code follows, a confusing UX, a data inconsistency — **do not quietly follow, mirror, or accept it.** Surface it and propose a fix, even when it's strictly "out of scope" for the task at hand.

- **Flag it plainly** the moment you notice it: what's wrong, where, and why it matters.
- **Propose a concrete fix** and let the user decide (per *No assumptions*: present, then wait). Don't unilaterally expand scope — but don't bury the issue either.
- **Default to fixing the root cause, not inheriting it.** If new code would have to reproduce an existing bug to stay "consistent" with the old code, that is the signal to fix the root cause — not to copy the bug forward.

"It's pre-existing," "the other code does it too," or "it already worked this way" is **never** a reason to ship the same problem again or to gloss over it. Naming the problem and offering the fix is the default; silently accepting it is the failure mode this rule exists to prevent.

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

## Editing the Claude `@claude` workflow (`.github/workflows/claude.yml`)
- The automated per-PR review (`claude-code-review.yml`) has been **removed** — code review is done locally via `/code-review` (see *Push, PR, and review workflow* below), so the GitHub auto-review was a duplicate spend. Only `claude.yml` (the on-demand `@claude` assistant) remains.
- `claude.yml` runs `claude-code-action`, whose GitHub App token exchange requires the workflow file on a PR branch to be **byte-identical to the version on `main`**. If a feature branch edits it, every run on that branch dies at startup with `App token exchange failed: 401 Unauthorized — Workflow validation failed`.
- So any change to it must land on `main` FIRST, via a small dedicated PR, then be synced onto the feature branch — **never edit it on a feature branch alone.** This bites often; treat it as a hard rule. (Even the dedicated PR's own run will 401, because that PR is the one changing the file — that's expected, ignore it; the merge still works.)

## Push, PR, and review workflow
- **Push freely — do NOT ask before pushing.** Commit and push as the work reaches a coherent state; there is no ask-first gate on pushing.
- **Open the PR at the first reviewable gate.** As soon as the work is in a reviewable state, open the PR — don't sit on it waiting for everything to be finished. Jesse reviews on GitHub.
- **Jesse's MANUAL review comes first; the AI `/code-review` runs ONLY post-merge.** Open the PR and hand off to his manual review. Do **not** run `/code-review` at PR-open or alongside his manual review — his review will likely request changes, so an earlier AI review just re-reviews soon-to-be-stale code and **wastes money**. Jesse merges manually; **after the merge**, run `/code-review` on the final merged state.
- **Default review effort is `medium`** (`/code-review medium`); **billing-critical changes use `high`–`xhigh`** — when the diff touches the billing core (`FastApiBackend/src/memberships/`, `payments/`, `sync/`, `reconciler/`, the Stripe webhooks, or anything that decides how real members are charged), a mis-bill is expensive, so the deeper review is worth the spend.
- **`/code-review` agents run on OPUS.** The built-in review workflow's `agent()` calls inherit the session model, and the review fan-out multiplies whatever that model costs — so a session on a pricier model silently runs a whole fleet of pricier reviewers, and passing "use opus" in the args does NOT work. Pin it explicitly: launch the workflow, take the script path from the tool result, edit every `agent()` call's opts to add `model: "opus"`, and relaunch with `{scriptPath}`.
- This local `/code-review` is **the** code review — there is no automated per-PR review on GitHub anymore (removed to avoid the duplicate spend).
- **List every finding to Jesse in PLAIN TEXT — it's his log.** When a `/code-review` completes, output the COMPLETE findings list as plain conversation text: every finding (never truncated or bundled), ranked, each with its verdict (confirmed/plausible), `file:line`, and a one-line failure description. The workflow's own result/output file does NOT count — Jesse never sees it; the list must be typed out in the reply itself. And because text written between tool calls may not be rendered, the list must be delivered as the FINAL message of a turn (no tool calls after it) so it actually displays. Once the list is delivered, start fixing the OBVIOUS ones immediately — no need to wait for a reply. Findings that are plausibly intended behavior, design judgment calls, or larger refactors wait for Jesse's ruling.
- **Correctness over quickness when addressing findings.** Fix the root cause (including any pre-existing issue the review surfaces, per *Don't silently inherit existing problems*), re-run the full verification (lint + tests + analyze + the live tests the change touches), and update the docs/skills the change affects — never the fastest patch that just silences a comment.

## No inline prompts or SQL
- Never inline an LLM/agent prompt in code. Every prompt lives in its own `.md` file and is read at use; code may hold the path, never the prompt text.
- Never inline SQL in code. Every query lives in its own `.sql` file and is read at use.
- This holds repo-wide and for every system, including ones not using prompts or SQL yet.
- **Exception — short integration-test queries.** Tests are not production code: a short read/assert/setup query may be inlined as a `text("SELECT …")`/`text("UPDATE …")` literal directly in the test or a `tests/helpers/db_reads.py` / `db_writes.py` helper. This is the established, deliberate test convention (those helpers themselves inline; `tests/helpers/sql/` holds only the cleanup `DELETE`s). It applies to **test code only** — every query in application/service code still lives in its own `.sql` file with no exceptions.

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
- **A fresh worktree has NO env files — run the setup script before running or testing anything.** From inside the newly-created worktree, run **`/var/home/jm/Documents/CombatDen/codebase/setup_worktree_env.sh`** (a **local, gitignored** helper — lives in the root checkout, excluded via `.git/info/exclude`, never committed; machine paths hardcoded). It deterministically copies every per-system secret env file from the root checkout into the worktree at the same relative path and **symlinks every poetry `.venv`** it finds in the root (auto-discovered), and it self-ensures the local ignore rules in `.git/info/exclude` (`setup_worktree_env.sh` + a `.venv` pattern with no trailing slash so it matches the `.venv` **symlinks**). (These env files are gitignored, so a clean worktree won't contain them; every system + its tests/seed fails or warns until they're present.) The env set it copies: `FastApiBackend/.env`, `CRM/.env.dev`, `CRM/.env.prod`, `Database/python_data/.env`, `VideoService/.env`, `VideoService/.env.prod`, `ThemeService/.env`; the `.venv` symlinks cover FastApiBackend, VideoService, ThemeService, LandingPage, and the `CRM/deploy*` / `ThemeService/deploy-assets` deploy-tooling venvs. It also symlinks the large **untracked** `VideoService/videos` pool (~23k yaml files the seed's video step / `import_yaml` loads — a fresh checkout lacks it, so without the symlink `make seed`'s video step imports 0 videos). The copies + symlinks stay gitignored (verify with `git check-ignore`) and are never committed. Re-run the script if the root's secrets are later regenerated.

## You are an orchestrator / advisor — implement through subagents

The main session acts as an **orchestrator and advisor, not the line implementer**: it plans, decides, reviews, and reports, while **subagents do the implementation work** so the main context stays lean and strategic. Delegate any substantial edit-heavy or search-heavy work — building out a service, a multi-file refactor, a docs sweep, a broad investigation — to a subagent with a well-scoped brief (context, exact files, conventions to follow, verification to run). Keep in the main session only what genuinely needs its judgment: decisions, founder Q&A, plan shaping, cross-workstream sequencing, reviewing subagent output, and small in-flight fixes that would cost more to brief than to do.

Pick each subagent's model by the task using the *Workflow / sub-agent model defaults* section below (Sonnet for mechanical volume; Opus for the initial/major explore, for planning agents, and for well-defined substantial builds and design passes — a planning agent is always a fresh agent given its context, never a fork). Never run two subagents concurrently over the same files — parallelize only across disjoint systems/domains.

### Handoff packets — brief every subagent as if it has no chat context
Write each delegation as a self-contained packet; the subagent sees only what you hand it at creation. Include: the repo path and exact objective; the files/systems in scope and anything explicitly out of scope; the evidence to return (files, line refs, commands run, diffs, failures, uncertainties); the verification to run (lint + tests + analyze + the live flow the change touches) and what success looks like; and **stop conditions** — if the code doesn't match the brief, a command keeps failing after a reasonable retry, or the task needs out-of-scope files, STOP and report instead of improvising.

### Vet delegated work — reports are leads, not facts
Treat every subagent report as a lead to confirm, not a fact to trust. Before you act on a high-impact finding, open a PR, or tell the user something is done: reopen the important cited files, confirm the relevant line refs / failures, and review the final diff against the task. Lighter agents gather the signal; truth-judgment stays in the main session.

## Workflow / sub-agent model defaults
Pick the sub-agent/workflow model by the TASK, not by habit:
- **Sonnet — small tweaks and simple, mechanical work.** Contract ports, per-file edits, data passes, broad read-only recon/searches, straightforward test updates — anything where the steps are obvious and volume is the cost driver. Use the 1M-context variant (`model: 'sonnet[1m]'` on `agent()` calls / subagent launches, or the phase/run model override; plain `'sonnet'` only where the harness rejects the `[1m]` variant) so large passes don't compact mid-task. Sonnet is still the default for a *large* mechanical fan-out, on cost alone.

  **Rate limits are no longer a reason to avoid an Opus fan-out.** The limits were raised, so a wide Opus burst is fine when the work needs judgment — don't split it into batches or downgrade to Sonnet to dodge a limit that isn't there. Pick the model by the task; let cost, not throttling, be the only tie-breaker.
- **Opus — everything that needs judgment.** Three jobs, all Opus:
  - *The initial/major explore pass* — the broad recon that must not miss anything.
  - *The planning agent* — whenever an implementation plan is being drawn up. Always a **fresh agent, never a fork**: spawn it new and hand it exactly the context it needs at creation. (A fork inherits the parent's model and ignores a model override, so it can't be steered anyway.)
  - *Design work and well-defined substantial builds* — UI/UX design passes (e.g. an `impeccable` redesign), and any single meaty task whose spec is clear but whose execution quality matters more than throughput. One well-scoped Opus agent beats a Sonnet agent that ships something functional-but-rough.

  **A planning agent stops at the plan.** If a task feels like it needs a planner on the keyboard, that's the signal the plan isn't thorough enough — send it back for a deeper plan rather than letting the planning agent implement.

## Planning: always author a visual plan

Whenever a task needs a plan — anything beyond a truly trivial, unambiguous one-liner whose diff you could describe in a single sentence — author that plan as a **structured visual plan** through the `plans` MCP (the `/visual-plan` skill, backed by the self-hosted `PlanServer` at `localhost:3939`), never as a chat-only wall of prose. Surface the returned `localhost:3939/...` link so I can review it there. (For a genuinely trivial change, skip the plan and just make it — a padded one-step visual plan is worse than none; that gating is the skill's own rule.)

**Plan like you only get one shot.** I do not want to rebuild this or burn turns on needless iterations, so the plan must be exhaustive *before* any code is written. Make no assumptions and think about everything:

- **Make no assumptions.** Where a decision has more than one reasonable answer, either resolve it in the plan with explicit rationale, or put it in the plan's bottom Open Questions block and ask — never guess and never silently pick. (This is the repo-wide *No assumptions* rule; the plan is where it is enforced.)
- **Think about everything.** Read the real files, schemas, endpoints, and patterns first and name actual files/symbols/data shapes — do not invent them. Cover the hard-to-reverse decisions (data-model shape, wire format, public ids, auth/ownership boundaries), every state and edge case, error/empty/loading paths, migrations and rollout, tests and verification, cost/perf, and the downstream systems the change touches. For each step, name what it **reuses** (existing code, schema, helpers) before what it adds.
- **Detailed enough to execute without re-deriving.** Someone — or a subagent — handed only the plan must be able to build it correctly the first time. Spell out each step, the exact files it changes, and how it will be verified end-to-end.
- **Right the first time.** If the plan feels thin, or you catch yourself planning to "figure it out while coding," the plan is not done — deepen it (send it back to the Opus planning agent per the model defaults) rather than starting to build. A deeper plan is always cheaper than a rebuild.
- **Design inside plans goes through Opus + `impeccable` too.** When a plan includes UI/UX design — wireframes, screen flows, canvas artboards in a visual plan — that design work is authored by a **dedicated Opus subagent loaded with the `impeccable` skill**, even at wireframe fidelity. The main session briefs it and assembles its output; it never draws the screens itself. (This is the plan-time mirror of the *Impeccable before UI/visual changes* rule below.)

## Impeccable before UI/visual changes
Before making **any** UI/visual change, run the `impeccable` design pass first — ideally in a **dedicated subagent** (Opus, per the model defaults) so it can focus on the design without carrying the whole task's context. This is the default for anything that changes what a screen looks like: new screens, redesigns, new widgets, layout/hierarchy changes, restyles. **This applies at every fidelity, including planning: wireframe-level design inside a visual plan is also authored by a dedicated Opus `impeccable` subagent** (see the Planning section above).

**Exception:** a small, targeted tweak whose visual goal is *completely unambiguous* (a copy fix, a one-value spacing/color correction, wiring an already-designed component) can be done directly. Any ambiguity, or any non-trivial size, → use `impeccable`. When unsure which side of the line you're on, use `impeccable`.

## Calling the FastApi Backend
- The authoritative request/response contract is the backend's Pydantic schemas in `FastApiBackend/src/<domain>/<domain>_schema.py`. Before writing or modifying any code that calls a backend endpoint (seed scripts, tests, other services), read the matching schema there and include every field listed under `required`.
- `Database/openapi.json` is an **optional, gitignored** local convenience dump. It is never committed, never expected to exist, and must never be flagged as missing or stale. To regenerate it locally from a running backend: `curl localhost:8000/openapi.json > Database/openapi.json`.
