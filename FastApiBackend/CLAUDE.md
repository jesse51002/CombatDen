# FastAPI Coding Standards

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills are living documents

When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new domain, a renamed module, an added dependency, a rule the code has outgrown on purpose, an architecture change), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Workflow

**Always Ask Clarifying Questions**
- Before starting implementation, ask clarifying questions about ambiguous requirements
- Don't assume intent — confirm with the user when the spec is unclear or has multiple valid interpretations
- Better to ask upfront than to build the wrong thing

**NEVER Write Tests Around Production Bugs**
- If a test fails because production code is broken, **fix the production code** — do not reshape the test to pass against the broken path
- If you cannot fix the production code in the same change (scope, unknowns, waiting on approval), **stop and surface the bug to the user**. Do not ship a test that silently accommodates a known defect
- Tell-tale patterns that mean you are writing around a bug — never do any of these:
  - Calling the same service method twice ("force a settle sync", "re-run so the writeback is visible") when the contract says once should be enough
  - Substituting a lower-level path for the documented flow (e.g. flipping a column via SQL because the real cancel/update path is broken)
  - `pytest.mark.xfail` or `pytest.mark.skip` with a reason that points at a production line number instead of an external constraint
  - Loosening an assertion ("either 7500 or 7600 is fine") when the actual root cause is a bug on our side, not genuine non-determinism from a third party
  - Docstrings that say "since X doesn't actually Y, we do Z instead" — if you catch yourself writing that comment, file the bug instead
- When a test discovers a production bug, the correct workflow is: (1) reproduce, (2) **write the test against the correct behavior so it fails loudly**, (3) fix production, (4) watch the test turn green. Not: (1) reproduce, (2) reshape the test until it passes.
- Regression guards for *already-fixed* bugs are fine and encouraged — the distinction is that the production code is correct now and the test locks it in. A test shaped around a *live* bug is not a regression guard, it is camouflage.

## General Principles

**SOLID Principles**
- Single Responsibility: Each class/module has one well-defined purpose
- Open/Closed: Open for extension, closed for modification
- Interface Segregation: Many specific interfaces over one general-purpose

**Other Core Principles**
- DRY (Don't Repeat Yourself): Single source of truth for each piece of logic
- KISS (Keep It Simple): Favor simplicity over complexity
- YAGNI (You Aren't Gonna Need It): Don't add features until needed
- Separation of Concerns: Separate different aspects into distinct sections

## Python Standards

**Imports**
- **ALWAYS add imports at the top of the file** - all imports must be at the beginning
- Good: All imports grouped at the top, before any code
- Bad: Imports scattered throughout the file or added in the middle of code
- **NEVER use relative imports** - always use absolute imports from `src`
- Good: `from src.users.schemas.user_schema import UserCreateRequest`
- Bad: `from .schemas.user_schema import UserCreateRequest`
- Bad: `from ..services.user_service import UserService`
- This ensures clarity and prevents import errors when modules are moved

**Constants**
- **NEVER use magic numbers or hardcoded values** — all constants must live in `src/core/config.py` (as `Settings` fields) or as `UPPER_CASE` final variables at the top of the file
- Good: `settings.db_pool_size` or `MAX_RETRIES = 3` at the top of the file
- Bad: `pool_size=10` buried inside a function or constructor

**Enums**
- **ALWAYS use enums instead of raw strings for known value sets** — statuses, types, categories, discriminators, etc. must be `str, Enum` classes
- **NEVER use hardcoded strings** when an enum exists — all comparisons, match/case, filter values, and Pydantic field types must use the enum
- **ALWAYS reuse enums and schemas from the Database package** (`../Database/python_data/schema/`) when they exist — import via `from schema.<module> import <Enum>` (available through `src/shared/db_schema_path.py`). Never redefine enums that already exist in the Database package.
- Pydantic auto-serializes `str` enums to their string values in JSON responses, so no manual conversion needed
- Use `Literal[MyEnum.value]` for Pydantic discriminated union fields, not `Literal["some_string"]`
- Good: `value: list[MemberStatus]` with `class MemberStatus(str, Enum): active = "active"`
- Bad: `value: list[str]` with hardcoded `"active"`, `"trial"` scattered through the code

**PEP 8 Naming**
- Modules/packages: `my_module.py`
- Classes: `UserService`, `PostRepository`
- Functions/variables: `get_user_by_email`, `user_count`
- Constants: `MAX_CONNECTIONS`, `API_TIMEOUT`
- Private: `_internal_var`, `__name_mangled`

**Formatting**
- Max 79 characters per line (99 acceptable)
- 2 blank lines around top-level functions/classes
- 1 blank line between methods

**Code Complexity & Nesting**
- **Limit deep nesting** - avoid nesting more than 3 levels deep
- **Extract functions when nesting gets complex** - create new helper functions/methods
- Good: Extract nested logic into separate, well-named private methods
- Bad: Deep nesting (4+ levels) makes code hard to read and maintain
- Example: Instead of `if/for/if/for/if/try`, extract the inner logic into `_validate_and_correct_item()`
- Benefits: Easier to test, read, and maintain; follows Single Responsibility Principle
- **Prefer flat functions with an orchestrator over deep nesting** (situational)
  - Write small, focused functions that each do one thing
  - Use an orchestrator function to call them in sequence
  - Good: `orchestrate()` calls `_validate()`, `_transform()`, `_persist()` sequentially
  - Bad: `orchestrate()` contains all logic in deeply nested blocks
  - Use judgment — simple logic doesn't need to be split into 5 tiny functions
- **Keep files small and focused** — don't put everything in one giant file
  - Split logically distinct concerns into separate modules (e.g., formatters, query builders, mappers)
  - A file with 5+ responsibilities is too big — break it up
  - Good: `formatters.py` for formatting, `queries.py` for SQL, `service.py` for orchestration
  - Bad: One 500-line service file that formats, queries, maps, and orchestrates

**Type Hints**
- **MUST have type hints on ALL function parameters and return values**
- Use native collections for Python 3.9+ (`list[str]`, `dict[str, int]`)
- Use `Optional[T]` for nullable values
- Use `Union` or `|` for multiple types
- Create type aliases for complex types
- No exceptions - even simple functions must have type hints

**DateTime Handling**
- **ALWAYS use UTC timezone for datetime fields**
- Good: `datetime.now(timezone.utc)`
- Bad: `datetime.now()` (uses local timezone)
- Use `default_factory=lambda: datetime.now(timezone.utc)` for Pydantic fields
- Store all timestamps in UTC, convert to user's timezone only in the frontend
- **NEVER do manual date arithmetic for months/years** — use `dateutil.relativedelta` instead. Manual calendar math has too many edge cases (leap years, month-end clamping, etc.)
- Good: `start + relativedelta(months=3)`, `start + relativedelta(years=1)`
- Bad: Manual modular arithmetic with `calendar.monthrange`, `date.replace(year=...)`
- `timedelta` is fine for days/weeks only

**Async/Await**
- Always await coroutines
- Use async-compatible libraries (`httpx`, `aiohttp`, `asyncpg`, `aiofiles`)
- Use `asyncio.gather()` for concurrent execution
- Never use blocking operations (`time.sleep`, sync `requests`)
- Always close connections with async context managers

**HTTP Requests**
- **ALWAYS add timeout to HTTP requests (default to 30 seconds)**
- Good: `httpx.get(url, timeout=30.0)`
- Good: `async with httpx.AsyncClient(timeout=30.0) as client:`
- Bad: `httpx.get(url)` (no timeout - can hang indefinitely)
- Use custom timeouts for specific endpoints if needed (e.g., `timeout=60.0` for slow APIs)

**Dependency Management**
- **ALWAYS use `poetry add <package>` to add dependencies**
- **NEVER manually modify pyproject.toml or poetry.lock**
- Use `poetry add --group dev <package>` for development dependencies
- Use `poetry add --group test <package>` for test dependencies
- Let Poetry handle version resolution and lock file updates

## Project Structure

**Domain-Driven Architecture**
```
src/
├── main.py                 # Application entry point
├── config.py               # Configuration
├── database/               # Database utilities
│   ├── session.py
│   └── base.py
├── auth/                   # Authentication domain
│   ├── auth_router.py      # API routes
│   ├── auth_schemas.py     # Pydantic models
│   ├── auth_models.py      # Database models
│   ├── auth_service.py     # Business logic
│   ├── auth_repository.py  # Data access
│   ├── auth_dependencies.py# Dependencies
│   └── auth_exceptions.py  # Custom exceptions
├── users/                  # Users domain
│   └── ...
└── posts/                  # Posts domain
    └── ...
```

**Domain-Prefixed File Names**
- **All files within a domain folder must be prefixed with the domain name**
- Good: `members/members_router.py`, `members/members_service.py`
- Bad: `members/router.py`, `members/service.py`
- This prevents confusion when multiple domain files are open in the editor (e.g., distinguishing `members_router.py` from `auth_router.py` in editor tabs)

**Why Domain-Driven**
- Clear boundaries between business domains
- Easy to scale and maintain
- Teams can work independently
- Promotes separation of concerns

## FastAPI Patterns

**Dependency Injection (dependency_injector)**
- Use `dependency_injector` with `DeclarativeContainer` for all dependency management
- All injectable dependencies must be defined as providers in `src/core/dependencies.py`
- Route handlers using `Provide[...]` must have the `@inject` decorator
- New domain modules must be added to `wiring_config.modules` in the container
- Use `Annotated` type aliases for clean route signatures (`DbSession`, `SupabaseClient`, `CurrentUser`)
- Good: `DbSession = Annotated[AsyncSession, Depends(Provide[Container.db_session])]`
- Good: `@inject` on any handler or dependency function using `Provide[...]`
- Bad: Importing `settings` directly — use container injection instead
- **Never import Container in service/shared modules** — DI wiring (`Provide[Container.xxx]`) belongs only in router files. Shared classes should use `self` and receive dependencies via constructor.
- Chain dependencies for authorization
- Apply common dependencies at router level

**Router Organization**
- One router per domain/resource
- Use RESTful principles (GET, POST, PUT, DELETE)
- Plural nouns for resources (`/users`, not `/user`)
- Path parameters for IDs, query parameters for filters
- Proper HTTP status codes (200, 201, 204, 400, 404, 500)

**Pydantic Models**
- Separate schemas for create, update, and response
- Create custom base model with shared config
- Use validators for complex validation
- Update schemas have optional fields
- Response schemas exclude sensitive data
- Use `EmailStr`, `HttpUrl`, built-in validators
- **Update requests must separate IDs from mutable data** — the request model contains identity fields (path parameters or top-level fields) and a nested `data` model with only mutable optional fields. This allows the service to extract change keys from `data` and validate them against the immutable columns guard (`validate_mutable_columns` from `src/shared/column_guard.py` + frozensets in `schema.immutable_columns` from the Database package).
- Good: `RewardUpdateRequest(data: RewardUpdateData)` where `RewardUpdateData` has only mutable optional fields and the reward_id comes from the URL path
- Bad: Flat update model mixing PKs, immutable columns, and mutable fields together

**Error Handling**
- Create custom exception hierarchy
- Register exception handlers globally
- Use specific exception types
- Include meaningful error messages
- Customize validation error responses

**Logging and Exception Strategy**
- **API/Router layer**: Use `logger.error()` with `exc_info=True` to log full stack traces
  - Good: `logger.error("Request failed", exc_info=True)`
  - Always import logging and create logger: `logger = logging.getLogger(__name__)`
  - Log before raising HTTPException to capture full context
- **Service/Repository/Util layers**: Just raise exceptions with relevant error messages
  - Good: `raise ValueError("Invalid URL format")`
  - Good: `raise HTTPException(status_code=404, detail="Resource not found")`
  - Bad: Don't log in service/util layers - let API layer handle logging
  - Focus on clear, descriptive exception messages that help debugging
- **Layer Separation**: API logs + handles, Services raise + describe

**Middleware**
- CORS must be first in middleware stack
- One purpose per middleware
- Proper ordering: CORS → Logging → Auth → Rate Limiting

## Database Patterns

**SQL Files**
- **Store SQL queries in `.sql` files**, not as inline strings in Python
- Place SQL files in a `sql/` subfolder within the domain (e.g., `src/members/sql/all_view.sql`)
- Use `src/shared/sql_loader.py`'s `load_sql(filepath, variables)` to load and template them
- Use `{variable_name}` for structural parts (e.g., WHERE clauses) and `:param_name` for bind parameters
- Good: `load_sql(SQL_DIR / "all_view.sql", {"where_clause": where})` then pass params to SQLAlchemy
- Bad: Inline SQL strings in service files

**Repository Pattern**
- Separate data access from business logic
- One repository per model
- Methods: `get`, `get_multi`, `create`, `update`, `delete`
- Use `selectinload` to avoid N+1 queries
- Keep repositories focused on data operations

**Service Layer**
- Contains business logic and validation
- Orchestrates repository calls
- Handles transactions
- Validates business rules
- Returns Pydantic schemas, not ORM models

**Layer Separation**
- Router → Service → Repository → Database
- Router handles HTTP concerns
- Service handles business logic
- Repository handles data access
- Never skip layers

## Computed-Status Views

Tables whose "status" is a function of multiple date columns expose
that derivation through a Postgres view rather than repeating the
`CASE` expression in every query. Example: `members_with_status`
(in `Database/supabase/schemas/members.sql`) wraps the `members`
table and adds `status` (`trial` / `active` / `inactive`) and
`last_class_days_ago`. All read-paths (`list_members.sql`,
`counts_members.sql`, `member_detail.sql`) SELECT from the view.
Writes go directly to the underlying table.

When you add a similar derived field, prefer extending an existing
`*_with_status` view or adding a new view — never duplicate the
derivation across SQL files.

## Security

**Authentication & Authorization**
- Authentication is handled by Supabase Auth — do not implement custom auth
- Validate Supabase JWT tokens in FastAPI using dependency injection
- Use dependency injection for auth checks
- Use Supabase RLS (Row Level Security) for authorization at the database level

**Input Validation**
- Always validate with Pydantic
- Sanitize HTML content
- Use parameterized queries
- Validate file uploads

**Configuration**
- CORS: specific origins only in production
- Rate limiting on public endpoints
- Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
- HTTPS only in production
- Environment variables for secrets

## Documentation

**Code Documentation**
- Docstrings for all public functions/classes/modules
- Document parameters, return values, exceptions
- Keep docstrings updated with code changes

**API Documentation**
- Specify `response_model` for all endpoints
- Use `summary` and `description` parameters
- Document all possible status codes
- Use tags to organize endpoints
- Mark deprecated endpoints with `deprecated=True`

**Versioning**
- Use URL path versioning (`/api/v1`, `/api/v2`)
- Maintain separate docs per version
- Document breaking changes
- Provide migration guides

## Code Quality Checklist

- [ ] Follows SOLID principles
- [ ] Type hints on all functions
- [ ] Proper async/await usage
- [ ] Domain-driven structure
- [ ] Repository pattern for data access
- [ ] Service layer for business logic
- [ ] Pydantic validation on all inputs
- [ ] Custom exception handling
- [ ] Comprehensive tests
- [ ] Security best practices
- [ ] Complete documentation
- [ ] No secrets in code
- [ ] Proper error messages

## Linting

**IMPORTANT: Always run `make format` after making code changes**
- Run `make format` before committing any changes
- This auto-fixes lint issues and formats code
- This ensures code quality and consistency across the project

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**

## Database

**Schema Location:** `../Database/supabase/schemas/` contains all Supabase table definitions with RLS policies.
- Never modify migration files directly — only edit schema files
- All tables use Supabase RLS for row-level authorization

