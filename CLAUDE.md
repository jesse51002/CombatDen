# Monorepo Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## No inline prompts or SQL
- Never inline an LLM/agent prompt in code. Every prompt lives in its own `.md` file and is read at use; code may hold the path, never the prompt text.
- Never inline SQL in code. Every query lives in its own `.sql` file and is read at use.
- This holds repo-wide and for every system, including ones not using prompts or SQL yet.

## Organization
- Each system (backend, frontend, database, etc.) lives in its own top-level directory.
- The root directory must stay clean: no application code, no config files for individual systems.
- Each system directory has its own CLAUDE.md with system-specific coding standards.
- Template CLAUDE.md files for common system types are in `claudes/` — copy and customize for each new system.

## Adding a New System
- Create a new top-level directory with a clear, descriptive name (e.g., `Backend/`, `WebApp/`, `MobileApp/`, `Database/`).
- Add a CLAUDE.md inside it. Start from the relevant template in `claudes/` and customize for the project.
- If the new system shares data contracts or code with other systems, document the cross-references in both CLAUDE.md files.

## Cross-System References
- When one system depends on artifacts from another (e.g., backend reads schema definitions from Database/, frontend uses an OpenAPI spec from Backend/), document the dependency path in the consuming system's CLAUDE.md.
- Use relative paths from the system directory (e.g., `../Database/schemas/`).

## Calling the FastApi Backend
- The authoritative request/response contract lives in `Database/openapi.json` (a regenerated OpenAPI dump).
- Before writing or modifying any code that calls a backend endpoint (seed scripts, tests, other services), read the matching request schema in `Database/openapi.json` and include every field listed under `required`.
