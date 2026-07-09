# FastAPI Coding Standards

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new domain, a renamed module, an added dependency, a rule the code has outgrown on purpose, an architecture change), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## README — keep it current

Two living documents describe this system, both kept in sync with the code (exactly like this file):

- **`README.md`** — a **simple** overview chart (CRM → FastApiBackend → Supabase + Stripe) plus the domain list and the load-bearing conventions.
- **`architecture.mermaid`** — the **full** internal graph, mirroring the real DI wiring in `core/dependencies.py`. Everything lives in **one `FastApiBackend` box** with **flat internals** (routes + every service, including the cross-cutting **`PaymentSyncService`** whose fan-in stays visible) and exactly **one nested group, `Payments`** (the Stripe core). `CRM`, `Supabase`, and `Stripe` sit **outside** the box; the box's external arrows are drawn at the box level — one arrow to **`Supabase`** (our DB), one to **`Stripe`** — so there's no `db_pool` hub and no hairball of per-service arrows.

Whenever the API surface or architecture changes — **a route or service added / removed / renamed**, a new domain/router, a changed DI dependency, a new external dependency, an auth/data-access change, or the CRM↔backend wiring status — **update both `README.md` and `architecture.mermaid` in the same change** so neither drifts. Author/edit the charts with the `mermaid-creation` skill and follow its rules (top-down `TB`, sibling-only edges, fixed palette, **no `~~~`** — Mermaid-9-safe — render + `check_siblings.py` validation).

One deep-dive diagram sits beside these: **`payment_sync.mermaid`** — the step-by-step orchestration flow of the payment-sync engine (`update_payments_recurring`), referenced from `README.md`. Its keep-in-sync owner is the **`sync-guide`** skill (update the diagram in the same change as the engine, per that skill); it follows the same `mermaid-creation` rules and validation.

## ⚠️ Payment sync + memberships — critical billing infrastructure, human in the loop

`src/memberships/` — and especially the payment-sync engine in
`src/sync/` — is **the most critical code in
this backend: it decides how real members are billed.** A mistake here mis-bills
real customers, so it is edited under a stricter rule than the rest of the repo:

- **One approved piece at a time. Never a big sweep.** Propose the change, wait
  for explicit approval, then write — for **each** part, as you go. Do **not**
  build out multiple parts and present them together; do not "just build
  everything."
- This overrides any instinct to batch related edits. Even when several changes
  are obviously connected, land and get each one reviewed on its own.
- The deep domain knowledge for the engine lives in the **`sync-guide`** skill
  (a living document) — read it before touching `src/sync/`, and update it in the
  same change when the engine changes.

## Domain builds — settle before code, audit after

When a task builds or heavily reshapes a domain (tables + services + routes):

- **Lock the schema shape with the founder before writing migrations or service code.** Pause at every schema inflection point and get the structure approved — rework is most expensive here.
- **Confirm domain placement explicitly** — new domain vs fold into an existing one, and which domain owns the feature (per the root *No assumptions* rule).
- **No demo-only code paths.** Presets/demos/imports go through the production write paths and produce production-shaped data — no special-case logic.
- **Default to deterministic code over agent/LLM steps** for anything that can run as plain code after a user decision (diff-check → derive → save); an agent converses, the commit path is code.
- **When the build reaches "works", run the `refine-backend` skill** as the post-build audit before hand-off.

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

**Don't test retired or non-existent routes**
- When a route is removed or renamed, **delete its tests** — never keep a test that asserts the old path now returns 404/405. A "this route is gone" assertion has no behavioral value, silently rots as the router grows (a future unrelated route on that path flips it green or red for the wrong reason), and just adds noise. The same goes for asserting that a route which never existed is absent.
- Test the routes that **exist** and their real behavior (status codes, payloads, auth). Coverage of the API surface comes from the Pydantic schemas (`src/<domain>/<domain>_schema.py`) + the live router, not from negative existence checks.

**Integration tests must clean up exactly what they create (the `created` fixture)**
- Tests run against a **real shared local Supabase DB + a real shared Stripe test Connect account** — no transaction rollback, no ephemeral DB. Every test must delete exactly the rows/Stripe objects it created, and **never** the single seeded gym (`tests/seed_constants.py`) or any other shared/seed data.
- Use the function-scoped **`created`** fixture (a `CreatedResources` registry in `tests/conftest.py`); it deletes everything registered on teardown, FK-safe and best-effort. Two ways to register:
  - **Create-and-track wrappers** for the data factory: `await created.member(...)`, `.plan(...)`, `.discount(...)`, `.reward(...)`, `.payment_method()`, `.test_clock(...)` — prefer these over calling `tests/helpers/data_factory.py` directly so cleanup is automatic.
  - **Manual trackers** for objects a service returns: `created.track_customer/track_product/track_price/track_coupon(<stripe_id>)`, `created.track_plan_db(plan_id)`, `created.track_discount(discount_id)`, `created.track_member(member_id)`, `created.track_reward(reward_id)`, `created.track_redemption(redemption_id)` (a reward carries no Stripe object, so a redeem call's returned `redemption_id` is tracked manually).
- Teardown order is clocks → redemption rows (FK both a member and a reward — always first) → members → plans → discounts → rewards → Stripe customers → coupons → archive prices/products. Stripe prices/products can only be **archived** (`active=false`), not deleted; coupons and customers are deleted (customer-delete cascades its subs/invoices); a test clock cascades its own clock-scoped customer/subs/invoices, so don't separately track those. Cleanup helpers live in `tests/helpers/cleanup.py`.
- A test that needs special teardown ordering may keep its own `try/finally`, but the default is: register with `created` and let the fixture clean up.

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
- **NEVER use magic numbers or hardcoded values** — all constants must live in `src/core/config.py` (as `Settings` fields) or as `UPPER_CASE` final variables at the top of the consuming file
- **Inside `src/core/config.py` itself, EVERY constant is a `Settings` field — never a module-level `Final` variable.** The class is the whole point: fields are env-overridable, typed, and monkeypatchable in tests via `settings`. A module-level constant next to the class is the anti-pattern this rule exists to prevent (it crept in once and spread).
- Good: `settings.db_pool_size`, `settings.lock_ttl_seconds`, or `MAX_RETRIES = 3` at the top of the file that uses it
- Bad: `pool_size=10` buried inside a function or constructor; `LOCK_TTL_SECONDS: Final[int] = 60` at module level in `config.py`

**Enums**
- **ALWAYS use enums instead of raw strings for known value sets** — statuses, types, categories, discriminators, etc. must be `StrEnum` classes (`from enum import StrEnum`, Python 3.11+; ruff's `UP042` enforces this over `(str, Enum)` on this codebase's Python 3.13)
- **NEVER use hardcoded strings** when an enum exists — all comparisons, match/case, filter values, and Pydantic field types must use the enum
- **ALWAYS reuse enums and schemas from the Database package** (`../Database/python_data/schema/`) when they exist — import via `from schema.<module> import <Enum>` (available through `src/shared/db_schema_path.py`). Never redefine enums that already exist in the Database package.
- Pydantic auto-serializes `str` enums to their string values in JSON responses, so no manual conversion needed
- Use `Literal[MyEnum.value]` for Pydantic discriminated union fields, not `Literal["some_string"]`
- Good: `value: list[MemberStatus]` with `class MemberStatus(StrEnum): active = "active"`
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
  - Good: `orchestrate()` calls `_validate()`, `_transform()`, `_persist()` sequentially — **but inside a service class these are private methods (`self._validate()`), not module-level functions** (see the next rule)
  - Bad: `orchestrate()` contains all logic in deeply nested blocks
  - Use judgment — simple logic doesn't need to be split into 5 tiny functions
- **No loose module-level functions in a service file** — a file built around a service class must keep its helpers *inside* that class as private methods, never as bare `def`s hanging above or below the class.
  - When you "extract a helper" (above) inside a service, extract it as a **private method** (`self._foo(...)`), not a module-level `def`. A `@staticmethod` is fine when the helper uses no instance state.
  - If a helper genuinely doesn't belong on the class, pull it into its **own dedicated class/module** — never leave a standalone function floating next to a class.
  - Good: `MembersBillingDetailService._build_rank(self, ...)`. Bad: a bare `def _build_rank(...)` sitting below the class in the same file.
  - **Exception:** standalone, class-less *concern modules* (e.g. `formatters.py`, pure mappers like `payments_stripe_mappers.py` / `gyms_status_mapping.py`, `queries.py`) are function modules by design and stay as free functions — this rule is about service files built around a class.
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

**File Naming Within a Domain**
- **Every file inside a domain folder carries the domain name as a prefix.** The prefix makes the file's origin unambiguous when it appears in imports, tracebacks, or grep output.
- Good: `memberships/memberships_router.py`, `sync/service/sync_builder.py`, `plans/plans_schema.py`
- Bad: `memberships/router.py`, `sync/service/builder.py` (no prefix — ambiguous in isolation)
- **A service file's primary class and its file name must stay consistent.** The file name is the class's role in the domain; renaming one means renaming the other in the same change.
  - Good: `memberships_discounts.py` ↔ `MemberMembershipsDiscounts`, `sync_builder.py` ↔ `PaymentSyncBuilder`
  - Bad: renaming the file without renaming the class, or vice versa — a drifted name silently misleads every reader and every grep.

**Why Domain-Driven**
- Clear boundaries between business domains
- Easy to scale and maintain
- Teams can work independently
- Promotes separation of concerns

**Service-Layer Organization**
- When a service grows past one file, its pieces live **flat in `service/`** by default — sibling files, the facade as `service/<domain>_service.py`; helpers are `service/<domain>_start.py`, `service/<domain>_cancel.py`, etc.
  - Good: `memberships/service/memberships_service.py` (facade), `memberships/service/memberships_start.py`, `memberships/service/memberships_cancel.py` — all flat in `service/`.
  - Good: `sync/service/sync_service.py` (orchestrator), `sync/service/sync_builder.py`, `sync/service/sync_queries.py` — all flat in `service/`.
- **A large domain MAY group a distinct sub-concern cluster into a subfolder** when that materially aids clarity — flat stays the *default*, but a domain that has grown big enough to hold a self-contained multi-file sub-concern can put it in its own `service/<sub-concern>/` folder. Reach for this only for a genuine multi-file cluster, **never for a single file**.
  - Good: `videos/service/video_agent/` holds the conversational-agent wrapper (`video_agent_service.py`), a self-contained sub-concern of the otherwise-flat `videos/service/`.
  - **The class system is versioned schedules + computed occurrences** (single source of truth: the `class-system-guide` skill). A class = a `gym_classes` IDENTITY row + append-only `gym_class_schedules` VERSIONS (each freezing its `timezone` at mint); occurrences are never stored — the pure `ClassesExpander` (one schedule shape; each candidate date FANS OUT over its `weekday_slots` slot list, so a class may occur several times per day) wrapped by `ClassesVersionExpander` (ownership windows by `effective_from`, first-version-owns-the-past, SLOT-level dedup at `(original_date, original_time)`) computes them for every read. An occurrence's identity is its ORIGINAL slot `(class_id, original_date, original_time)` — what `member_attendance`, `class_signups`, and `class_instance_exceptions` key (their UNIQUEs include `original_time`); every occurrence-addressed API call passes the date AND time; exceptions/reschedules never re-key anything. **`ClassesVersionsService`** (`classes_versions_service.py`) is the only writer of `gym_class_schedules`: a schedule edit mints a version effective NOW and, in the same transaction, wipes future-keyed sign-ups / early check-ins / instance exceptions whose original slot the new shape no longer produces (exact wall-clock matches survive); soft-delete wipes everything future; `remint_timezone` is the gym tz-change hook. `PUT /classes/{id}` splits `identity` (in-place) vs `schedule` (a complete shape → mint), the discounts identity/values precedent.
  - The `checkin` domain decomposes its check-in into two DI-injected seams kept flat in `checkin/service/`: `checkin_class_resolver.py` (`CheckinClassResolver`, the one-way `checkin → classes` seam — loads the class identity + its schedule versions + the day's exceptions and resolves the occurrence via the injected `ClassesVersionExpander` into a `ResolvedClass`; purely a read, nothing written; a retroactive any-date check-in validates against whichever version owned that date; it also enforces the **early-check-in window** — an occurrence starting more than `settings.checkin_opens_hours_before_start` (2h) in the future is rejected, gating both single + batch check-in) and `checkin_member_gate.py` (the per-member gate: one evaluation feeds the `is_member` split — a kiosk (`is_member=True`) strict-gate **reject**, or a staff (`is_member=False`) path that records a **clean** check-in but returns **`requires_confirmation`** (nothing written, the reasons as `warnings`) for a warned one **unless `ignore_warnings`** overrides — which records with NULL/best-available attribution + the warnings surfaced), over `checkin_queries.py` / `checkin_writer.py` / `checkin_plan_selector.py`. There is deliberately **no facade**: the single-check-in router injects the resolver + gate directly (resolve, then gate), and `batch_checkin_service.py` injects the same two (resolve once, then loop the gate over a de-duped member list). Siblings `cycle_counts_service.py` / `streak_service.py` / `checkin_attendees_service.py` (read-only per-occurrence **combined roster** — see sign-ups below) round out the domain, all flat in `service/` — the attendance row's denormalized `occurred_at` feeds the streak / cycle-count / last-class window SQL; streak additionally joins `gyms` to bucket weeks in the gym's CURRENT-local timezone (not UTC — see the class-system-guide skill), the others stay join-free. Check-in **reversal** also lives here: `checkin_reverser.py` (`CheckinReverser`) is the reusable per-member reversal core — `reverse(session, member_id, gym_id, class_id, original_date, points_worth)` deletes that member's attendance row by key, claws back the points (floored at 0), drops one `class_attended` activity, and reverses the auto-end on the charged trial / one_time pack, all in the caller's OPEN transaction (no commit). It imports **nothing** from `src.classes`. `checkin_remover.py` (`CheckinRemover`) is the thin single-member wrapper the remove endpoint injects.
  - **Sign-ups (reservations)** also live in `checkin` (NOT a new domain): `signup_service.py` (`SignupService`) creates/removes a member's reservation for an occurrence — `POST /api/v1/signup` + `DELETE /api/v1/signup`, both gated by `verify_can_view_member` (staff-principal-for-a-gym-member OR member-for-self, same as check-in; a staff principal is an owner/admin — trainers have no accounts). A sign-up is a reservation, **not attendance** — `member_attendance` is still only written by a check-in; a signed-up member who never checks in is a no-show, never auto-counted. `create` validates the occurrence via the version expander, stamps `original_time` from the resolved slot, resolves the effective `max_capacity` (`gym_classes.max_capacity` overridden per-occurrence by `class_instance_exceptions.new_max_capacity`; NULL = unlimited, never blocks) then, when limited, reads `CheckinQueries.get_signup_or_attended_members` — the **DISTINCT signed-up-OR-attended union** (`class_signups` ∪ `member_attendance` by `(class_id, original_date, original_time)` — capacity pools are per exact SLOT, one SQL file `signup_capacity_count.sql`) — and rejects with `ValueError("Class is full")` only when this member ISN'T already in that set and the set is already at capacity. The write is idempotent (`ON CONFLICT (class_id, member_id, original_date, original_time) DO NOTHING` → `already_signed_up=true`, still 200). **The check-in capacity gate reads the same union.** **The combined roster** — `GET /api/v1/checkin/attendees` — returns everyone who signed up OR attended an occurrence, each flagged `signed_up` / `attended` (`Attendee.log_id`/`plan_id`/`item_id` NULL when not attended) (`roster_for_occurrence.sql`). The schedule board (`src/classes`) adds `signup_count` + `attendance_count` per occurrence via plain cross-domain table reads (`classes_signup_counts.sql` / `classes_attendance_counts.sql`) — sanctioned `classes → checkin`-table (not code) reads.
    - **Deliberate exception to the one-way seam (`classes → checkin`):** `ClassesUndoService` (in `src.classes`) depends on `CheckinReverser` — the OPPOSITE of the documented one-way `checkin → classes` direction — looping it per attendee inside its shared `teardown_occurrence` (reverse attendance + delete sign-ups for one date), which is itself the single teardown that BOTH cancel entry points, the future-reschedule path, and `ClassesVersionsService`'s version-change wipe route through. So the per-member reversal has a **single** implementation. It is cycle-free precisely because `CheckinReverser` imports nothing from `src.classes` (the DI container builds `checkin_reverser` before all consumers). Don't flag this `classes → checkin` edge as a layering violation — it is intentional.
    - **The `gyms → classes` edge:** `GymsService.update_gym` calls `ClassesVersionsService.remint_timezone` on every save that carries a `timezone` (deliberately not gated on "did it change" — the gym row commits before the per-class remint, so a changed-value gate would skip a retry after a partial failure forever; the per-class deep-equal skip makes a re-save a cheap self-heal). A same-shape version mint per live class; wall-clock matching keeps every future-keyed row. Documented, deliberate.
  - Bad: `memberships/service/memberships/member_memberships_service.py` — a sub-subfolder wrapping a *single* group / file.
- The orchestrator / facade **lives inside `service/` as `<domain>_service.py`**, grouped with the files it orchestrates — never floating one level above.
  - Legacy note: `members/service/management/members_management_service.py` predates the flat rule and uses a nested layout (`management/` subdir with `members_management_create.py`, `_update.py`, …). That layout is not wrong for that domain, but new domains use the flat layout described above.
  - Bad: `members/service/members_management_service.py` floating above a sibling `management/` folder.
- A genuinely standalone service with no peers stays as a single file at the `service/` top level — fine (a future one-file service belongs flat at `service/`, not buried in a one-member subdir).
- **Don't add a nesting level for a single file/group.** If a folder would only ever hold one related set, keep those files flat in `service/` instead of burying them (e.g. webhook handlers live directly in `stripe_webhooks/service/`, not in a `handlers/` subdir). The subfolder allowance above is for a genuine *multi-file* sub-concern, not a single file.
- No bare module-level helper functions in a service file — fold them into the service class as private methods (see *Code Complexity & Nesting → No loose module-level functions in a service file*).

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
- **Discounts are a deliberate variant of this rule, not a violation.** A discount is a two-table identity/version model (`gym_discounts` identity + immutable `gym_discount_values` versions), so `DiscountUpdateRequest` splits the mutable data **by destination** into two sub-models — `identity` (rename in place) and `values` (mint a new version) — instead of one flat `data`. The model shape itself encodes which table each field writes (no runtime field-partition set), while the service **still** runs the same `validate_mutable_columns(GYM_DISCOUNTS, …)` guard over the combined change keys. `discount_id`/`gym_id` stay top-level for the auth `gym_id` check. See `src/discounts/schema/discounts_schema.py` + `service/discounts/discounts_update.py` and the `discounts-guide` skill.

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

**Billing / Stripe error status codes — never 502/503/504**
- Stripe-or-upstream failures in billing endpoints always return **500 Internal Server Error**, never 502/503/504. The 5xx proxy auto-retry family (502/503/504) causes reverse proxies and load balancers to replay the request automatically; auto-retrying a mutating billing op (charge, cancel, refund, reprice, freeze, …) risks duplicate side-effects. A partial batch result (some items succeeded, some failed) returns **207 Multi-Status** (a 2xx, also never auto-retried) with the per-item succeeded/failed split in the body; a total failure is 500.

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
- **Tests are exempt** (per the root `CLAUDE.md`): a short read/assert/setup query in an integration test may be inlined as a `text("SELECT …")`/`text("UPDATE …")` literal — directly in the test or in a `tests/helpers/db_reads.py` / `db_writes.py` helper (those helpers inline by design; `tests/helpers/sql/` holds only the cleanup `DELETE`s). This is the established test convention; application/service code never inlines SQL.
- **NEVER cast a bind parameter with `:param::type`** (e.g. `:waiver_ids::jsonb`, `:id::uuid`). SQLAlchemy `text()` over asyncpg cannot bind a parameter that is immediately followed by `::`, so Postgres raises `syntax error at or near ":"` and the query 500s. **Always use the functional cast `CAST(:param AS TYPE)`** instead.
  - Good: `CAST(:waiver_ids AS JSONB)`, `CAST(:member_id AS UUID)`
  - Bad: `:waiver_ids::jsonb`, `:member_id::uuid`
  - This applies to `.sql` files **and** any SET/VALUES clause built dynamically in Python (e.g. an f-string `f"{col} = CAST(:{col} AS JSONB)"`, never `f"{col} = :{col}::jsonb"`). This bug has recurred — it bit the membership-plans update path.
- **NEVER write a bare `:word` placeholder inside a SQL `--` comment.** `text()` scans the WHOLE statement — comment lines included — for `:name` bind markers, so a generic placeholder (`:col`, `:param`, `:x`) in a comment becomes an orphan bind param no code supplies, and the query 500s with `A value is required for bind parameter '<word>'`. Describe params in prose or a non-colon form (`the col column`, `<col>`) instead. (A real, always-bound param name in a comment is fine because it's supplied; `:col::type` is also safe — the trailing `::` suppresses it — but a standalone `:col` in a comment is not.) This bit `update_rank.sql`, whose comment used `:col` as a placeholder.

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
`CASE` expression in every query. Example: `member_memberships_status`
(in `Database/supabase/schemas/member_memberships.sql`) wraps
`member_memberships` and derives `status`
(`active` / `cancelled` / `ended` / `frozen`) from `cancel_date`,
`end_date`, and the **subject member's** freeze window on `members` (the
view joins `members` on the membership's own `member_id`, NOT its
`paid_by_member_id` — freezing a member pauses only that member's own
memberships, regardless of who pays). The member
read-paths (`src/members/sql/crm_views/*.sql`, `member_details/*.sql`)
SELECT from this view; writes go directly to the underlying table.

Member-level status is membership-derived (from `member_memberships_status`),
NOT stored on `members` — there is no `member_status` column or table.

When you add a similar derived field, prefer extending an existing
`*_status` view or adding a new view — never duplicate the
derivation across SQL files.

## Ranks domain

`src/ranks/` owns the per-gym rank ladder. **The full model lives in the
`ranks-guide` skill (the source of truth) — the two-level `gym_ranks` shape,
`sub_rank_type` (`none`/`stripes`/`div`), the effective-count rule, the leaf
invariant, the reconcile matrix, the `rank_changed` anchor, presets, and the
reads' internals. Read it before touching anything rank-shaped.** Only the
how-to-work-here facts belong here:

- **Facade + concerns.** `RanksService` (`ranks_service.py`) keeps
  single-rank CRUD (`create`/`update`/`get`/`list`/`delete`) and the
  `is_rank_enabled` toggle itself; everything member / reorder / preset /
  read shaped is pure delegation to concerns sharing a lean `RanksBase`:
  `RanksMembers` (the only member-writing paths), `RanksReorder`
  (`ranks_reorder.py` — main-only two-phase reorder), `RanksPresets`
  (seed-from-preset + preset reads), and `RanksReads` (the paginated
  boards). DI (`core/dependencies.py`) wires them via `ranks_members` /
  `ranks_reorder` / `ranks_presets` / `ranks_reads`; the router injects
  only the facade.
- **Immutable vs. writable.** `main_rank_num_order` is update-immutable
  (`GYM_RANKS` frozenset) — `POST /reorder` is its only mover;
  `current_rank_id` / `current_sub_index` are `MEMBERS`-immutable (ranks
  endpoints are the only rank-change path). `image_url` and
  `sub_rank_image_overrides` are ordinary user-writable fields.
- **SQL + DI edge.** Every query is its own `.sql` (`load_sql`), bound
  `CAST(:x AS T)` never `:x::t` (`update_rank` builds a dynamic SET of
  per-column casts). The `gyms → ranks_members` edge: `GymsService.update_gym`
  reconciles members on a `sub_rank_type` change (mirrored by `from_preset`).
- **Reads.** `GET /ready-to-promote`, `GET /{rank_id}/members`, and
  `GET /{rank_id}/sub-rank-counts` — the two `/{rank_id}/...` reads **derive
  the gym from the rank** (`get_rank` first → 404 if missing → verify the
  employee on the rank's gym), never a client `gym_id`.

## Security

**Authentication & Authorization**
- Authentication is handled by Supabase Auth — do not implement custom auth
- Validate Supabase JWT tokens in FastAPI using dependency injection
- Use dependency injection for auth checks
- Use Supabase RLS (Row Level Security) for authorization at the database level
- **Staff principals are owner/admin ONLY — trainers have no accounts.** A `gym_employees` row with `employee_type='trainer'` is instructor DATA (a name/photo shown on classes), never a login: the DB forbids a trainer `user_id` (`chk_trainer_has_no_account`), and every staff auth check in `src/shared/auth.py` (`verify_gym_employee`, `verify_can_view_member`'s staff branch, and the `_for_member` variants) filters to owner/admin explicitly. Never design a feature around a trainer logging in.

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

**`ruff check` is the gate; do NOT run `make format` / `ruff format`.**
- The repo is not ruff-format-clean: a blanket format churns unrelated
  pre-existing lines and pollutes diffs.
- Run `.venv/bin/python -m ruff check src/ tests/` (broken venv shebangs —
  always invoke via `python -m`) and fix what it reports; hand-format the
  lines you touch to match the surrounding style.
- `ruff check --fix` on the files you changed is fine; whole-repo
  formatting is not.

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**

## `videos` domain (`src/videos/`)

The `videos` domain (`src/videos/`) also hosts the LLM-powered spec authoring and conversational
agent plus the RAG read surface. Five routes cover the spec/agent + RAG surface
(all `verify_gym_employee`-gated EXCEPT the member rec + rec-click routes, which are
`verify_can_view_member`):

| Route | What it does |
|---|---|
| `GET /api/v1/gyms/{id}/video-spec` | Return the gym's latest spec (reads `gym_video_spec_latest` view) |
| `POST /api/v1/gyms/{id}/video-agent` | One conversational turn — also handles accept via `accepted_spec` in body |
| `POST /api/v1/gyms/{id}/video-agent/refine-from-feed` | Fold manual curation signals from `gym_video_feed` into a new `feed_update` version |
| `GET /api/v1/gyms/{id}/members/{member_id}/video-rec` | The member's next single rotating-category RAG rec — rotates the served genre by the member's served-rec count, records the pick, returns `{rec_id, category, video}` (`verify_can_view_member`; 404 when the member isn't in the path gym OR no category yields a video) |
| `POST /api/v1/gyms/{id}/members/{member_id}/video-rec/{rec_id}/click` | Record a member opening a rec: stamp `clicked_at`, log a `video_clicked` activity, fire a profile refresh (`verify_can_view_member`; 404 when the rec isn't the member's) |

**ONE unified feed read backs everything (`VideoFeedService.load_feed_page`).** `GET /api/v1/gyms/{id}/videos`
(`verify_gym_employee`) always MERGES the owner section (`video_run_id IS NULL`) with the gym's latest
COMPLETED run — there is **no owner/source param**. It serves **only enriched-AND-accepted** videos:
the SQL **INNER JOIN**s `video_rag` (the enriched-only gate) so a row shows only once it has an
embedding, and `?rejected` selects `scan_status` `accepted` vs `rejected`. `?member_id` is a read-only
ranking hint (the candidate set is always the path gym's feed, so it can't leak — a member-facing route
is a future concern, this stays staff-facing). **This same read backs the member rec** (`limit=1`,
filtered to one genre).

**Ranking — one axis, two σ-scaled nudges** (all in `videos_load_feed_page.sql`, wrapped in a CTE so a
window stddev is available):
- `axis` = cosine distance to the member embedding (`r.embedding <=> CAST(:member_embedding AS vector)`)
  when one is bound, else gym `relevance_index`. A NULL `:member_embedding` is detected via
  `CAST(:member_embedding AS text) IS NULL` (mirroring the CAST-to-text/CAST-to-vector pattern so
  asyncpg binds a NULL cleanly — do NOT split into two SQL files for the null-embedding case).
- `sigma` = `COALESCE(stddev_samp(axis) OVER (), 0)` over the whole candidate set.
- `penalty_units` = `SUM(power(0.5, age_seconds / :half_life_seconds))` over the member's prior serves of
  this video (`member_video_recs`), 0 rows when `:member_id` is NULL — a just-served video ≈ 1, an old
  serve ≈ 0.
- `adjusted` = `axis − owner·:bump_fraction·sigma + penalty_units·:bump_fraction·sigma`, `ORDER BY
  adjusted ASC, relevance_index ASC, video_id ASC`. Owner videos nudged NEARER, watched videos nudged
  FARTHER, symmetric and σ-scaled. Two `Settings`: `video_feed_bump_sigma_fraction` (0.10) and
  `video_watch_penalty_half_life_days` (7.0, ×86400 → `:half_life_seconds`), injected into
  `VideoFeedService` (no `settings` import — DI constructor args).

**Separate UNGATED owner listing** — `GET /api/v1/gyms/{id}/videos/owner` (`verify_gym_employee`,
`load_owner_videos` / `videos_load_owner_videos.sql`): owner-section rows only, **LEFT JOIN** `video_rag`
(NOT the enriched gate) exposing `enriched` so the CRM can badge "processing…", `ORDER BY curated_at DESC
NULLS LAST`. An owner-added video is visible here the INSTANT it's added — before enrichment — which the
enriched-gated served feed can't show. `GymVideoCard` carries `video_id` (required), `owner_added`
(feed selects `video_run_id IS NULL AS owner_added`), and `enriched` (default `True`; only the owner
listing sets it `False`).

There is **no semantic-search route** — it was removed (zero callers).

**Agent interaction model — the agent does ONLY conversation; save/query-gen are deterministic.**

The agent has **zero tools**. It converses to propose a spec; its proposal output
(`SpecProposal`) **always** pairs a short chat `message` with the criteria `draft` (criteria
only: disciplines + keep/avoid descriptions), so a proposal is never silent — the message is
appended to the chat while the criteria show in the highlighted panel. When the owner presses Accept, the frontend sends
`accepted_spec` in the next `AgentTurnRequest` and the backend commits it deterministically:
diff guard → query generation → save. The agent is then run on a short outcome note so it can
acknowledge and invite further changes (the conversation stays open, `saved=True`).

**Services (flat in `service/`):**

- **`VideoSpecService`** (`video_spec_service.py`) — spec DB read/write: `load_latest`,
  `save_version(gym_id, draft, queries, *, source)`. `queries` is a separate arg — never in the draft.
- **`VideoQueryGenerator`** (`video_query_generator.py`) — LLM structured query gen: `generate(disciplines, videos_desc, avoid_desc, count)`. A **two-call** flow: call 1 researches the niche's content landscape (`LandscapeResult` — channels / creators / series, hallucination tolerated, never validated), call 2 turns criteria + that rendered landscape into queries (roughly one third landscape-targeted, the 5-cluster spread still governs the whole set). `count` is required — `VideoSpecAuthoring` injects `settings.video_query_count`.
- **`VideoSpecAuthoring`** (`video_spec_authoring.py`) — shared deterministic commit: diff guard → query gen → save.
  `commit(gym_id, criteria, *, source) -> VideoSpecView | None`. Returns `None` when criteria are unchanged.
  It only saves the new version — there is no enqueue step. An `admin_update` version it just saved is
  picked up by the VideoService worker on its own next tick (the worker derives the due gym from
  timestamps; see the VideoService CLAUDE.md).
- **`VideoFeedRefiner`** (`video_feed_refiner.py`) — LLM feed→criteria refine; delegates commit to `VideoSpecAuthoring`.

**`VideosService` (`videos_service.py`) is the domain FACADE** — composes `VideoFeedService`,
`VideoSpecService`, `VideoSpecAuthoring`, `VideoFeedRefiner`,
`VideoRecsService`, and `VideoRecClickService`. Exposes: `load_latest_spec`,
`save_accepted_spec` (→ authoring.commit), `refine_from_feed`,
`get_video_rec`, `record_rec_click`, plus all feed operations
(`load_feed_ids`, `load_pool_videos`, `load_feed_page` — which takes the optional `member_id`,
`load_owner_videos`, owner add/remove/keep). The conversational agent uses it for
the accept-path and first-turn state seeding (plain calls, not tools). Template catalog reads live
in `PresetsTemplateService` (presets domain); showcase reads live in `ThemeShowcaseService` (theme domain).

**Serve-path invariant (feed + rec):** every "latest run" subselect on the serve path filters
`AND status = 'completed'` so a mid-flight `running` run never becomes latest and blanks the feed —
this covers the unified feed page (which the rec reuses at `limit=1`) and the owner keep/reject curation
writes (which target the run currently being served). Beyond the completed-run filter, the serve path
also gates on **enriched AND accepted** — the feed's `INNER JOIN video_rag` is THE serve invariant: an
accepted row with no embedding is invisible until the worker enriches it (the ungated `/videos/owner`
listing is the only read that shows an un-enriched owner video). The `video_run.status` column exists for exactly this
(the VideoService worker sets it; the backend has no worker-control surface — the worker derives its
own due gym from timestamps already in the schema, so there is nothing to enqueue and no status route).

**RAG read surface — single rotating-category rec + optional personalized feed + rec-click.**

The per-member RAG profile is **ONE LLM-written summary + ONE embedding stored on the `members` row**
(`video_profile_summary` / `video_profile_embedding` / `video_profile_embedding_model` /
`video_profile_built_at`, all nullable, service-role-written, in the `MEMBERS` immutable frozenset) —
not a sidecar table. A small chat model (`video_profile_summary_model`) turns the member's facts (rank,
gym disciplines, most-attended classes in a 90-day window, and recently `video_clicked` videos' title +
`video_rag` summary) into a short taste paragraph; that paragraph is embedded once and its embedding is
what the rec + the personalized feed rank against `video_rag.embedding`. The `vector(1536)` DDL is a
**cross-service contract** — every produced vector is length-checked against `settings.video_embedding_dim`
(a mismatch raises, not writes a wrong-width vector). Embeddings are pgvector text form (`'[0.1,0.2,...]'`),
bound `CAST(:x AS vector)`.

**The profile is (re)built ONLY by `refresh_if_due` — reads never build.** There is no
build-on-read: `refresh_if_due` (fired fire-and-forget by the click + class-booking triggers) is the
only path that renders + embeds a new summary. Every read (`verify_member_in_gym`, `load_embedding`,
the rec, the personalized feed) tolerates a missing embedding by ranking without similarity.

- **`MemberVideoProfileService`** (`member_video_profile_service.py`) — builds (refresh-only) + reads.
  `verify_member_in_gym(member_id, gym_id)` is the **READ-ONLY ownership guard**: it verifies the member
  belongs to `gym_id` (raising `MemberNotInGymError`, a `ValueError` subclass, on a mismatch or missing
  member — this stops a caller authorized to view a member, `verify_can_view_member` only checks the
  member not the path `gym_id`, from ranking a DIFFERENT gym's feed) and NEVER builds. `refresh_if_due`
  is the trigger gate — same guard, then rebuilds when the embedding is missing OR `video_profile_built_at`
  is older than `video_profile_refresh_cooldown_days` (3d), a no-op within the cooldown. `_build` reads
  member facts in ONE query → renders `prompts/member_profile_summary.md` → `complete_structured`
  (summary model) → `embed` (embedding model) → dim-check → UPDATE the members row.
  `load_embedding(member_id)` reads the pgvector text back (None when unbuilt).
  `MemberNotInGymError` maps to 404 at the route.
- **`VideoRecsService`** (`video_recs_service.py`) — `get_rec(gym_id, member_id) -> MemberVideoRec | None`:
  serves ONE video at a time, **rotating the served genre category** through
  `settings.video_rec_category_rotation`. It is a **thin wrapper over the unified feed** — it drives the
  rotation and records the pick, but the ranking + candidate query live in the ONE
  `VideoFeedService.load_feed_page` (there is no separate rec SQL). `verify_member_in_gym` →
  `idx = (COUNT of the member's member_video_recs rows) % len(rotation)` picks the starting category;
  within a category it calls `feed_service.load_feed_page(gym_id, video_type=category, member_id=member_id,
  limit=1, offset=0)` and takes the first card if the page is non-empty (the feed itself reads the
  embedding once and applies the owner-boost + decayed-watch-penalty ranking above). A category that
  yields **no** card falls through to the next in the rotation (wrapping); the first genre with a video
  wins. **The rec advances on a re-serve via the decayed watch penalty baked into `load_feed_page` — there
  is NO already-served anti-join.** A just-served video is nudged back on the next call, so a category with
  enough clustered candidates surfaces a different pick; a sparse category (one video) legitimately
  re-serves the same one. The pick is APPENDED to `member_video_recs`
  (`video_recs_record_insert.sql`, `RETURNING rec_id`) and returned as `MemberVideoRec{rec_id, category,
  video}` (`video` is the `GymVideoCard`, carrying `video_id`). Returns `None` (→ route 404) when no
  category anywhere yields a video. `MemberNotInGymError` propagates (→ 404).
- **`VideoRecClickService`** (`video_rec_click_service.py`) — `record_click(gym_id, member_id, rec_id)`:
  in one txn stamps `member_video_recs.clicked_at` (first click only — idempotent via `clicked_at IS
  NULL`, scoped to member+gym) and logs a `video_clicked` `member_activities` row (carrying `video_id`
  + `rec_id`); on the first click it fires `MemberVideoProfileRefreshRunner.start`. A repeat click is
  idempotent (`clicked=false`, no re-stamp/re-log/re-fire); an unknown rec for this member+gym raises
  `RecNotFoundError` → 404.
- **`MemberVideoProfileRefreshRunner`** (`member_video_profile_refresh_runner.py`) — fire-and-forget
  runner (mirrors `MembershipsInvoiceFetchRunner`: a `ClassVar` task set, a done-callback crash logger,
  `drain()` in the `main.py` lifespan). `start(member_id, gym_id)` fires `refresh_if_due` detached; a
  refresh failure NEVER surfaces to the caller. Two triggers wire it: the **video-click** (inside
  `VideoRecClickService`) and the **class sign-up** (router-level composition in `checkin_router.py`'s
  `signup` handler, after a successful `create` — keeps `SignupService` decoupled from the videos domain).

There is **no semantic-search service** — `VideoSearchService` and the `/videos/search` route were
removed (zero callers). The rec's `category` is typed as the existing `VideoGenre` enum (`schema.video`),
never a separate abstraction (there is no mood-bucket map). Member activity writers use the shared
`MemberActivityType` enum (`schema.member_activity`). Response schemas: `schema/video_recs_schema.py`
(`MemberVideoRec` (`rec_id` / `category: VideoGenre` / `video: GymVideoCard`) and `VideoRecClickResponse`
— there is no `RecCandidate` wrapper; the card already carries its `video_id`); the profile summary
schema is `schema/member_profile_schema.py` (`MemberProfileSummary`, char-capped). SQL:
`sql/member_profile_load.sql` / `member_profile_source.sql` / `member_profile_update.sql`,
`videos_load_feed_page.sql` (THE unified feed + rec read), `videos_load_owner_videos.sql` (the ungated
owner listing), `videos_load_feed_ids.sql` (the merged, enriched-gated preview candidate set),
`video_recs_served_count.sql`, `video_recs_record_insert.sql` (`RETURNING rec_id`),
`video_rec_click_update.sql` / `video_rec_load.sql` / `member_activity_video_click_insert.sql`.

The agent wrapper lives in `service/video_agent/`:

- **`VideoAgentService`** (`video_agent_service.py`) — `agent_turn` only. No tools registered.
  Accept-path calls `videos_service.save_accepted_spec`; normal first turn seeds current-spec
  context by prepending it to the user message.

**Schemas:**
- `schema/video_spec_schema.py`: `VideoSpecDraft` (criteria only — no `queries` field),
  `VideoSpecView` (read, includes queries/source/created_at), `LandscapeResult` (query-gen call 1),
  `QueriesResult` (query-gen call 2).
- `schema/video_agent_schema.py`: `AgentTurnRequest` (`message`, `history`, `accepted_spec`),
  `AgentTurnResponse` (`reply`, `draft`, `question`, `history`, `saved`, `usage`).
  `AgentQuestion` (`question`, `options` 2–6, `multi_select`) — the agent can ask a
  multiple-choice question rendered as selectable chips in the CRM. `SpecProposal`
  (`message` + criteria `draft`) — the agent's finished-proposal output; a proposed draft
  **always** carries a `message` (mapped to `AgentTurnResponse.reply`, appended to the chat).

**SQL:** `sql/video_spec_load_latest.sql`, `video_spec_insert_version.sql`, `video_feed_signals.sql`.

**Prompts live in `src/videos/prompts/*.md`** (per the monorepo no-inline-prompt rule). Code holds
the file path, never the prompt text.

**LLM stack — litellm for regular calls; Pydantic AI for the conversational agent.**

The backend runs **Python 3.13** (`requires-python = ">=3.13,<3.14"`). litellm can't install on
3.14, so the backend moved to 3.13 to get both LLM frameworks.

- **Regular structured litellm calls** (`VideoQueryGenerator` — a two-call landscape→query flow;
  `VideoFeedRefiner` — one call) go through
  **litellm** via `src/shared/litellm_client.py` (`LiteLLMClient.complete_structured(prompt, schema,
  model)`). Model string is `settings.video_llm_model` in litellm's `provider/name` format (e.g.
  `anthropic/claude-sonnet-4-6`); the `provider/` prefix selects which API key to use.
- **The conversational agent** (`VideoAgentService`) uses **Pydantic AI** (`pydantic-ai-slim[anthropic]`)
  with an explicit `AnthropicModel` constructed from `settings.video_agent_model` (bare model name,
  e.g. `claude-sonnet-4-6`) and `settings.anthropic_api_key`. No env-variable writing,
  no `video_agent_llm.py` (that file was removed — all provider wiring is in `video_agent_service.py`).

**One-way layering rule:** `VideoAgentService` → `VideosService` (facade) → the regular services
(`VideoSpecService`, `VideoQueryGenerator`, `VideoFeedRefiner`, `VideoSpecAuthoring`). The regular
services **never** call `VideoAgentService`.

Related settings: `video_llm_model` (litellm format), `video_agent_model` (bare model name),
`anthropic_api_key`, `openai_api_key`, `gemini_api_key`, `video_agent_retries`,
`video_query_count` (queries per commit, injected into `VideoSpecAuthoring`).

RAG settings: `video_embedding_model` (litellm format, default `openai/text-embedding-3-small` — needs
`openai_api_key`), `video_embedding_dim` (1536, pinned to the `vector(1536)` DDL and shared by
`video_rag.embedding` + `members.video_profile_embedding`), `video_profile_summary_model` (small chat
model that writes the taste summary, default `anthropic/claude-haiku-4-5`, reuses `anthropic_api_key`),
`video_profile_refresh_cooldown_days` (3), `video_rec_category_rotation` (ordered `VideoGenre` list —
best-first genre order the single rec rotates through). The pick WITHIN a category is the top of the
unified feed for that genre (`load_feed_page`, `limit=1`) — cosine order to the taste embedding with the
owner boost + decayed watch penalty, governed by `video_feed_bump_sigma_fraction` (0.10) and
`video_watch_penalty_half_life_days` (7.0), the two feed-ranking `Settings` injected into
`VideoFeedService`. There is no per-rec score column and no rec-count setting.

**Versioned spec — readers always use the view, not the table.**
`gym_video_spec` is **append-only** (rows are never UPDATE'd; the table is a permanent version log).
Three writers append new version rows, each stamped with a `gym_video_spec_source` enum value:

- Agent accept / admin save → `admin_update` (via `POST /api/v1/gyms/{id}/video-agent` with `accepted_spec`)
- Preset import (`PresetsService`) → `system_update`
- Feed refiner → `feed_update` (via `POST /api/v1/gyms/{id}/video-agent/refine-from-feed`)

Read paths (including the `GET` endpoint) **always** query the `gym_video_spec_latest` view, which
surfaces the single most-recent version per gym. Do not `SELECT` directly from the raw
`gym_video_spec` table in a read path. Queries are stored in the spec's `queries JSONB` column (the
separate `gym_video_query` table was dropped when versioned spec shipped).

**DI providers (videos domain):** `litellm_client`, `video_spec_service`, `video_query_generator`,
`video_spec_authoring`, `video_feed_refiner`, `member_video_profile_service`
(defined before `video_feed_service`, which reads the embedding), `video_feed_service`
(defined before `video_recs_service`, which delegates the rec candidate query to it),
`member_video_profile_refresh_runner`, `video_recs_service`,
`video_rec_click_service`, `video_agent_service`, `videos_service`.

**DI providers (presets domain):** `presets_service`, `presets_template_service`.

**DI providers (theme domain):** `theme_showcase_service`.

There is NO separate `video_config` router or module.

## Image upload domain (`src/uploads/`)

`POST /api/v1/uploads/image` — a multipart image plus a `category` **form field** (`reward`,
`member`, `class`, `gym`, `rank`; not a query param) → stored in the `combatden-assets` S3
bucket under a `category`-named key prefix → returns a CDN URL
(`cdn.combatden.net/...?v=<content-hash>`). Used by the CRM's `ImageUploadPickerField`. Gated by
`Auth.verify_staff_principal` (owner/admin of ≥1 gym; no `gym_id` to scope). The 5 MB cap is
enforced before and after the body is read.

**Dependencies:** `boto3`, `python-multipart`. **Required `Settings`:** `assets_bucket`,
`aws_region`, `assets_cdn_base_url` (AWS creds via the boto3 env credential chain, not `Settings`).

## Database

**Schema Location:** `../Database/supabase/schemas/` contains all Supabase table definitions with RLS policies.
- Never modify migration files directly — only edit schema files
- All tables use Supabase RLS for row-level authorization

