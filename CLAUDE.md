# Monorepo Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills are living documents
When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them. This applies to every system's skills.

## CLAUDE.md is a living document

Every CLAUDE.md in this repo is a living document — exactly like a skill, it must track reality. Whenever code genuinely diverges from what a CLAUDE.md says (a new live backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, an architecture change), **update that CLAUDE.md in the same change** so the doc and the code never drift apart. Never leave one stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

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

## Workflows (multi-agent orchestration)
- **Default workflow agents to Sonnet** (`model: 'sonnet'` on `agent()` calls, or the phase/run model override) unless a task genuinely needs Opus-level reasoning. Workflows fan out many agents at once; running them on Opus is far more expensive and **hits rate limits** fast (a 75-agent Opus fan-out got rate-limited mid-run). Sonnet has higher throughput and lower cost — the right default for fan-out work like data passes, conversions, broad reviews, and per-file edits. Reserve Opus for the few agents that actually need deep reasoning.
- Keep concurrent fan-out reasonable; prefer Sonnet + batching over a huge Opus burst.

## Calling the FastApi Backend
- The authoritative request/response contract lives in `Database/openapi.json` (a regenerated OpenAPI dump).
- Before writing or modifying any code that calls a backend endpoint (seed scripts, tests, other services), read the matching request schema in `Database/openapi.json` and include every field listed under `required`.
