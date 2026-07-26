# CRM — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this app is

This is the CombatDen **gym admin web app** (CRM) — staff and owners managing their gym from a browser. It is **production software**: real Supabase auth, real FastApiBackend data over `dio`, Bloc state management, and Stripe billing. Treat every screen as something a paying gym depends on.

- **Web-only Flutter app** (no Android, no iOS target).
- **Architecture is feature-first** (see *Project Structure*): each feature owns its `bloc/`, `data/` (models + repositories), and `presentation/` (screens + widgets + dialogs + sections).
- **One feature is a shared MODULE rather than a screen.** `features/membership_flow/` owns no screen and no cubit — it holds what both membership-purchase surfaces render and obey, so a rule, a price string, a plan word or a component cannot be changed on one surface only. The two surfaces are the kiosk signup (`features/kiosk/`) and the staff start-memberships wizard (`features/member_details/.../start_memberships/`); each keeps its own orchestration, because that is where they genuinely differ (the kiosk takes a card before review, the desk settles after it) and it is the layer holding the kiosk's double-charge defences.
  - `domain/` — the rulebook: pure functions and plain data. Nothing in it may hold a widget, a cubit, async I/O or a repository call; state and I/O stay in the surface that owns them.
  - `presentation/` — the component set (`chrome/` for the step scaffold, shell contract, rail, foot and buttons; `models/` for the view models; `widgets/` for everything a step composes). `Flow*`-named, one public widget per file.
    - **Every component is stateless: data in, callbacks out.** A shared widget takes plain view models from `presentation/models/` (`FlowPersonView`, `FlowPlanSummary`, `FlowMoneyView`, `FlowSignedWaiverView`) and raises intent as callbacks — it never takes a surface's state type and never reads a cubit off the context. That is not style: a component holding `KioskSignupState` is shared in NAME only, because the second surface cannot construct one. Each host builds the view models from its own state (the kiosk in `features/kiosk/presentation/kiosk_flow_views.dart` + `kiosk_money_view.dart`), which is also where per-surface privacy rules live — the kiosk masks every identity line, the desk hands staff the full address.
    - **The SHELL is per-host, and the module owns none.** `FlowStepScaffold` assembles the rail + head + identity + body + foot into a `FlowShellParts` and hands it to the host's `shell` builder: the kiosk passes its full-screen `KioskStage` (via `features/kiosk/.../signup/kiosk_step_scaffold.dart`), the desk passes its `AppDialog` body. Same for the step spine — the host supplies `railSteps` + `railIndex`, because it is the host's own steps being mapped.
    - Two button files are a deliberate split, not a duplicate: `chrome/flow_buttons.dart` reads the scale so it renders at either surface's size, and the kiosk's `kiosk_buttons.dart` pins the `kiosk*` tokens for the lanes that are kiosk-only. Both wrap the same shared `AppPrimaryButton` / `AppOutlineButton`.
  - `config/` — `MembershipFlowScale` (the surface's TYPE ramp plus its form measure, all getters so light/dark keeps resolving through `themeController`) handed down by the `MembershipFlowTheme` `InheritedWidget`. A shared component asks for a ROLE (`scale.panelTitle`) and the surface's scale picks the `DesignConstants` token; the scale SELECTS between existing tokens and restates no value. It is deliberately **not** a `ThemeExtension` — this app never reads `Theme.of(context)` (see *Theming System*). Non-type tokens (colours, radii, spacing, icon sizes, shadows) still come straight from `DesignConstants` at the call site. The host mounts exactly one `MembershipFlowTheme` above its step switcher; a widget test pumping a shared component on its own must do the same, or `MembershipFlowTheme.of` asserts.
  - The kiosk's structural no-discounts rule survives all of it: `domain/discount_math.dart` is staff-only and the kiosk must never import it, and no shared component may import a staff-only module either. `test/features/kiosk/kiosk_forbidden_imports_test.dart` is the enforcement, and it walks three scopes: `lib/features/kiosk/` (the saved-card / payer-picker / discount ban plus the literal word "discount"), the shared component set (no staff-only module), and the WHOLE module — `lib/features/membership_flow/` may import neither `features/kiosk/` nor `features/member_details/presentation/`, since it is what both surfaces depend on.
- **A handful of screens are deliberate, scoped edge integrations** — reads (and in one case a narrowly-scoped write) against a service other than FastApiBackend, or public unauthenticated reads — rather than going through the authenticated `ApiClient`. They stay stateless per the *Hybrid state-management model* below and use `package:http` per the *Dependencies* section, never the CRM feature pattern. They are the exception, not the rule: the CRM feature stack (members, member detail, gym setup, billing) goes through the FastApiBackend via the authenticated `ApiClient`.

**Theme/design rules are not relaxed for any reason.** See *Theming System*.

**Impeccable before UI/visual changes.** Before any non-trivial UI/visual change here, run the `impeccable` design pass first — ideally in a dedicated Opus subagent so it can focus. A small, unambiguous tweak (copy fix, single token correction, wiring an already-designed component) can be done directly; anything with visual ambiguity or non-trivial size goes through `impeccable`. This applies at every fidelity, including planning — wireframe-level design for this app inside a visual plan is also authored by a dedicated Opus `impeccable` subagent. See the codebase-root `CLAUDE.md` "Impeccable before UI/visual changes" section for the full rule.

## Hybrid state-management model (documented and deliberate)

This app uses **two patterns side by side, on purpose**:

- **CRM feature screens use Bloc.** Anything backed by the FastApiBackend gets a `bloc/` + `data/` (models + repositories) + `presentation/` set, built on `flutter_bloc` + `equatable`. Events describe user/system actions; states represent UI state; repositories sit behind the bloc, never called directly by a widget. This is the standard for all new CRM features.
- **A documented exception for small, page-scoped reads.** A section that needs a read too small/isolated to justify a new event/state pair on an already-large bloc may instead run its own small, read-only side-read against a repository (the fetch lives in the widget, not on the bloc). A side-read may still *react* to the bloc's shared `refreshToken` to know when to re-fetch, but its data never becomes bloc state. This is for keeping a bloc from bloating with one-off reads on an already-built feature — not a way to avoid building a bloc for a genuinely new feature.
- **Edge / non-CRM screens stay stateless.** Screens that only render content or drive a read-only edge integration use `StatelessWidget` for pure display and `StatefulWidget` only for local UI state (tab index, scroll controller) or to host a `FutureBuilder` over an edge read. They do not need a bloc.
- **A screen can be mixed.** Some sections of a screen may be stateless/demo while others are live and bloc-backed — decide per-section, not per-screen.

When you add a feature that talks to the FastApiBackend, it gets a bloc. When you add a screen that only renders or drives an edge read, it does not. If you're unsure which side a new screen falls on, ask.

## Repository pattern + ApiClient (the CRM backend path)

- **All FastApiBackend calls go through `ApiClient`** (`lib/core/network/api_client.dart`). It wraps a single configured `dio` instance, attaches the **Supabase JWT** as a Bearer token on every request, applies a **30s timeout**, and on a **401 refreshes the Supabase session (time-bounded) and retries once**; if the refresh fails **or times out** it calls `ApiClient.onUnauthorized` (wired in `main.dart`) to sign the session out, dropping the auth gate back to the login screen. The refresh timeout is essential: gotrue treats a network/host-unreachable refresh failure as *retryable* and keeps retrying without emitting an event, so an unbounded refresh would hang the request — and with it the boot-time gym fetch — leaving the auth gate spinning forever instead of redirecting to login on an expired session. Never create a raw `Dio` or make bare HTTP calls for CRM data — use `ApiClient`.
- **For multipart image uploads, `ApiClient` exposes `postMultipart`.** `ImageUploadRepository` (`lib/core/uploads/`) wraps it and returns a CDN URL. The **single** upload UI is the shared `ImageUploadPickerField` widget (`lib/shared/widgets/form/image_upload_picker_field.dart`) — opens the system file picker via `image_picker`, uploads through `ImageUploadRepository`, and calls back (`onImageChosen`) with the CDN URL. It carries a `category` (the backend upload category) and an optional `defaultImageUrl` to preview a platform default (with a "choose your own" caption) before the user has uploaded one. When given a non-empty `poolImages` list it also renders a tray of tappable default-image chips below the preview — picking one fires the same `onImageChosen` callback synchronously (no upload), so a field can offer curated defaults and a custom upload side by side (the pool-URL lists live in `AppConstants`). It never validates itself: a host form marks it `isRequired` and passes an `errorText` on a failed submit (red border + inline message). There is **no** URL-paste variant — every image surface is a real CDN upload or a curated pool pick through this one widget; never build a parallel upload flow.
- **Repositories wrap `ApiClient`.** Each feature's `data/repositories/` exposes domain methods (`getMembersList`, `getMyGym`, `getMember`, …), takes an `ApiClient` in its constructor, converts JSON responses to models, and throws typed exceptions. Blocs depend on repositories, never on `ApiClient` directly. Keep the layering: **Screen → Bloc → Repository → ApiClient → backend.** Never skip a layer.
- **Read the Pydantic schemas (`../FastApiBackend/src/<domain>/<domain>_schema.py`) before calling any endpoint.** They are the authoritative request/response contract. Match the path, method, and every field listed under `required`; model `fromJson` must track the response shape exactly. When the contract changes, update the models in the same change. (`../Database/openapi.json` is an optional gitignored local dump — never committed, never expected to exist, never flagged in review.)

## Models & code generation

- **Models are `json_serializable`.** Each model declares `@JsonSerializable()` and a generated `*.g.dart` part. Add or change a model, then regenerate: `dart run build_runner build --delete-conflicting-outputs`. Commit the regenerated `*.g.dart` alongside the model. Never hand-edit a `*.g.dart`.
- **Resilient enum parsing.** Any enum parsed from JSON must have a safe fallback in its `fromJson` — `firstWhere(..., orElse: () => <default>)` — so a new backend enum value never crashes the UI. Status-like enums get an `unknown` variant; view-like enums fall back to the default (e.g. `all`). Every `switch` on such an enum must handle the fallback case.
- **Money is signed integer minor units** (cents). Model money fields are `int` / `int?` (negative = refund/credit), preserved end-to-end from the backend. Convert to a display string **only at the render layer** via the shared helper in `lib/core/utils/money.dart` — never hand-roll `amount / 100` at a call site.
- **DateTime:** display in local time, send UTC to the backend.
- **Backend string display:** capitalize lowercase backend strings (`'active'`, `'recurring'`) before display — the API hands them to us lowercase.
- **Some client enums are DISPLAY enums that are wider than the DB column, so never mirror a backend `WHERE … IN (…)` string-for-string.** `MembershipStatus` (`features/members_list/data/models/membership_status.dart`) is the live example: `member_memberships_status`'s `CASE` emits only `cancelled` / `ended` / `frozen` / `active`, and the backend then derives the extra client-facing values on top of a raw row — `overdue` is an `active` membership whose `next_due_date` has passed (`../FastApiBackend/src/shared/membership_status.py` + `sql/membership_overdue.sql`), `trial` / `dormant` / `no_membership` are likewise computed. So when a client rule has to agree with a backend guard, **map the guard's DB values through that derivation instead of copying its string list**: the shared rulebook's `_blockingStatuses` (`features/membership_flow/domain/plan_rules.dart`, behind `RecurringHeldGate`) is `{active, frozen, overdue}` precisely because that is how the guard's `status IN ('active','frozen')` reads on this side. Copying the two literals would silently under-block; adding a value the guard doesn't cover would refuse a sale the API accepts. Read the SQL, then ask which client values collapse onto each DB value.

## Error handling

- **Typed exceptions live in `lib/core/errors/exceptions.dart`** — `AuthException` (and its `InvalidCredentials` / `UserAlreadyExists` / `WeakPassword` / `EmailNotConfirmed` subtypes), `ServerException`, `NetworkException`, `DatabaseException`, `GymConflictException`. Repositories **throw + describe**; blocs **log + handle** (`log('...', error: e, stackTrace: stackTrace)` before emitting an error state) and surface a user-friendly message.
- Every bloc-backed screen renders explicit **loading / loaded / error** states from its state union, with a retry path on error.

## Authentication & access

- **Supabase auth gates the admin app, and only in `main.dart`.** `main.dart` boots Supabase (`SupabaseConfig.initialize`), provides the `LoginBloc`, and mounts the `AuthGate`, which routes: initial/loading → spinner, unauthenticated/error → `LoginScreen`, authenticated → **list every gym the caller's verified email matches a non-archived employee row at (`GET /api/v1/gyms/`, role-annotated per gym)** and route on the count: **0** → `GymSetupScreen`; **1** → the members workspace scoped to that gym (in a nested `Navigator` sharing the admin route table); **2+** → `GymPickerScreen`, then the workspace once a gym is chosen. Picking activates the gym via `selectedGym.setActiveGym(...)`, whose real UUID then scopes every member view. The whole authenticated subtree tears down on sign-out.
  - **Kiosk Mode intercepts the workspace.** While the app-root `KioskSessionCubit` is active, the authenticated branch mounts the member self-serve `KioskScreen` (`features/kiosk/`) — or the fail-closed `KioskLockedScreen` once the session has ended — **instead of** `_MembersWorkspace`, so the admin nested navigator + route table + `AppShell` never mount. The admin session and `selectedGym` stay live underneath; *leaving* kiosk is what signs out. Four things here are load-bearing and are easiest to break from OUTSIDE the feature: (1) the cubit is provided **non-lazy** in `main.dart` and starts in the synchronous `KioskStatus.restoring` state, which the gate renders as a neutral `LoadingScreen` — **never** `_MembersWorkspace` — so a boot or reload can't flash an admin route before the persisted flag is read; (2) `enterKiosk` **awaits** its flag persist before going active; (3) entering is itself a staff capability (`RolePolicy.canOperateKiosk`, gating the nav item); (4) every kiosk flow must balance `beginFlow`/`endFlow` — `KioskFlowCubit.goHome()` is the ONE abandon path, and a second one that skips `endFlow` stops the kiosk ever signing itself out at its 12-hour runway's lockout; (5) **there are no `AutofillHints` / `AutofillGroup` anywhere in `CRM/` and that is load-bearing** — the kiosk is a SHARED front-desk device, so autofill on a shared form widget would offer the previous member's address (or card) to the next person, and if hints are ever added the kiosk must explicitly opt out. The kiosk also runs its **own complete** type ramp (`DesignConstants.kiosk*`, which moves as a SET — never re-scale one role; the SIGNUP lane reads that ramp one hop away, through `MembershipFlowScale.kiosk()`), lifts every muted kiosk word to the AA-passing `text2nd`, and pins both QR tiles dark-on-white regardless of theme. **Everything else about Kiosk Mode — the runway and its server clock, fail-closed persistence, the fresh-card law (the kiosk never charges a pre-existing card: it always collects a fresh one, which always becomes the payer's default and replaces theirs — so an existing member can self-serve here, and the card step says so), the **two client-side plan-block rules** derived from the member's own history — the kiosk-only one-trial rule (per member; staff can still grant a repeat trial from the CRM) and the already-held recurring membership (per plan, mirroring the backend's own conflict SQL) — both are now the **one** shared rulebook's gates (`RecurringHeldGate` / `TrialOnceGate` in `features/membership_flow/domain/plan_rules.dart`), which the CRM's start wizard imports too, so there is no copy left to drift; mind the display-vs-DB status split under *Models & code generation* when reading them — the waiver run's **fail-CLOSED** already-signed skip (a waiver whose prior signature is at or above the re-sign floor per the existing by-member read is dropped from the queue, the deliberate inverse of those two fail-OPEN plan reads, with the 422 purchase gate as the authoritative backstop) — the **three-way start-response split** (all-created and PARTIAL both land on the per-person results receipt; only an all-failed start reaches the decline popup, whose "you haven't been charged" is true exactly there), the structural no-discounts rule, the two rejection shapes (`skip_reason` vs a stable `code`), the two separate class lists, the warmed gym-wide catalogues, the glance, the "Get the app" modal, the pinned per-step identity band, and the phase status — lives in the `kiosk-guide` skill. Read it before touching `features/kiosk/`.**
- **Signup requires Supabase email confirmation.** `register_form.dart` (`features/login/presentation/widgets/`) no longer auto-activates on submit — it drives a dedicated "verify your email" register state, and clicking the confirmation link auto-logs the person in once Supabase marks the address confirmed. A freshly-created `gym_employees` row stays `invite_status: pending` (backend-derived) until this completes.
- **Role model: 4 roles, gated client-side by `EmployeeRole` + `RolePolicy`.** `lib/core/auth/employee_role.dart` defines `EmployeeRole` (`owner | admin | frontDesk | trainer | unknown`, JSON-parsed with a safe `unknown` fallback); `lib/core/auth/role_policy.dart`'s `RolePolicy` extension is the **single** capability source (one boolean getter per capability, e.g. `canManageStaff`, `canViewDashboard`, `canCreateMembers`, `canOperateKiosk`) plus `landingRoute` and `canAccessRoute(path)` — nav filtering, route access, and section visibility all read these getters, nothing hard-codes a role comparison elsewhere. `lib/core/navigation/route_guard.dart`'s `redirectRouteFor` wraps `canAccessRoute` for `main.dart`'s route generation and the auth gate's initial route. A denied backend call surfaces as `ForbiddenException` (`lib/core/errors/exceptions.dart`), shown as a role-specific message. Full role/capability matrix and the backend enforcement it mirrors: **`employees-guide`** skill.
- **Front desk gets a READ-ONLY Gym catalog + the operational Dashboard.** `canViewCatalog` (staff: owner/admin/front desk) gates *reading* the `/memberships` tabs; `canConfigureCatalog` (owner/admin) is the *write* gate that every catalog create/edit/delete/promote/toggle/reorder affordance hides behind at the widget layer (via `selectedGym.role?.canConfigureCatalog ?? false`), so front desk views the plans/discounts/waivers/ranks tabs and rank detail but sees no Add / Edit / Delete / Promote / enable-toggle / sub-type / drag-reorder affordance. `canAccessRoute` splits `/memberships` to match: the editor/detail-form routes (`membershipDetails`, `membershipsWaiverEditor`, `membershipsRankEditor`, `membershipsRankPresets`) are tested FIRST and need `canConfigureCatalog`, while the broad `/memberships*` view prefix — including the read-only `membershipsRankDetail` — needs only `canViewCatalog`, so a front-desk deep-link can't reach an editor. `canViewDashboard` now includes front desk (they land on the Dashboard's OPERATIONAL cards — live attendance, overdue payments, upcoming classes), while `canViewGymAnalytics` (owner/admin) gates its overview/income cards (the Total Members hero now, a gym-income module later).
- **The public theme browser stays unauthenticated.** Its entry point (`lib/main_theme_browser.dart` → `ThemeBrowserApp`) never boots Supabase and never mounts the gate — it is a public marketing surface (see *Standalone theme browser*). Do **not** add auth to the theme target.

## Routing & URLs

- **Named routes in `lib/core/navigation/app_routes.dart`**, resolved by `_onGenerateRoute` + `_routeBuilders` in `main.dart`. No router package — section nav runs on the **nested `Navigator`** built in `auth_gate.dart::_MembersWorkspace` (it boots at the URL fragment for deep-linking, and the nav rail uses `pushReplacementNamed`).
- **The URL reflects the current section.** Because only the *root* navigator syncs to the browser bar by default, the nested navigator carries a `UrlSyncObserver` (`lib/core/navigation/url_sync.dart`) that calls `SystemNavigator.routeInformationUpdated` on push/replace/pop for the **addressable** top-level routes (`kAddressableRoutes`), so every section has a live, refreshable, shareable URL. The deliberate **hash** strategy stays (no `usePathUrlStrategy`); browser **Back/Forward is intentionally not wired** (would need the Router API / go_router). A detail screen reached by id should be deep-linkable the same way member detail is (`AppRoutes.memberDetailPath`/`memberIdFromPath`, synced via `UrlSyncObserver`): an id that fails to resolve (a 4xx) redirects to the section's list view, while a transient 5xx/network error keeps the retryable error view instead of redirecting away. A sub-route reached only via another screen's args (a form, an editor) keeps its parent section's URL rather than getting its own.
- **A tab inside a screen (not a nav-rail section) can still carry its own deep-linkable route** without becoming a top-level nav item — give it a route under its parent's path, keep tab switching as local widget state (no re-fetch of the tab's own data source on switch), and call the URL-sync helper to reflect the open tab so the nav rail item stays lit regardless of which tab is open.
- **Page-level routes must NEVER call a bare `Navigator.pop()`.** After a hard reload on a deep URL the nested Navigator boots with a single route (no synthetic back stack — see above), so a bare pop empties it and renders a blank white screen. Always use `popOrGoTo(context, <fallback route>)` from `lib/core/navigation/nav_pop.dart`, declaring the screen's natural parent route as the fallback; it pops when the navigator can, and deterministically replaces onto the fallback otherwise. Dialog and bottom-sheet pops are exempt — they pop the overlay, not a page, and always have a page beneath them to land on.

## Stripe billing

- Stripe is initialized in `main.dart` (`Stripe.publishableKey` from env, then `applySettings()`). Billing actions (charge card, refund, invoices, update card, plan/price changes) live in `features/member_details/presentation/dialogs/` and dispatch through `MemberDetailBloc` against FastApiBackend endpoints. `flutter_stripe` / `flutter_stripe_web` / `stripe_js` provide the web payment surface. Read the matching Pydantic schema in `../FastApiBackend/src/<domain>/<domain>_schema.py` before wiring any billing endpoint.
- **Cards are tokenized on the gym's Stripe Connect connected account, not the platform.** The backend runs direct-charge Connect (every customer / card / subscription lives on the gym's connected account), and a platform-owned `pm_…` cannot attach to a connected-account customer. `main.dart` only sets the platform publishable key, so the connected account is applied per-gym: `GET /api/v1/gyms/` carries `stripe_account_id` (`GymWithRole.stripeAccountId`), and `selectedGym.setActiveGym(...)` hands it to the `stripeAccountContext` seam (`lib/core/network/stripe_account_context.dart`), which sets `Stripe.stripeAccountId` + awaits `applySettings()` — re-applied on every gym switch, fail-closed on a null account (gym not onboarded). **The single shared `CardFieldBox` gates its Stripe `CardField` on `stripeAccountContext.isReady`/`paymentsAvailable`**, so the connected account is guaranteed applied before any card field mounts (a `CardField` binds to whichever JS Stripe object exists at mount time). This one seam covers all three card surfaces — the kiosk signup card step, the one-time custom card, and the update-card dialog. Under `flutter test` the real Stripe apply is no-op'd suite-wide (`test/flutter_test_config.dart`); the seam's logic is unit-tested with an injected recorder.

## Testing

- **Use `bloc_test` + `mocktail`.** Blocs hold the business logic, so they get the coverage: build the bloc with a mocked repository, `act` an event, assert the emitted state sequence (loading → loaded/error). Mock repositories and `ApiClient`; never hit a live backend in a test.
- Tests mirror the `lib/` tree under `test/`. Cover error and edge conditions, not just the happy path. `flutter test` (`make test`) before committing.

## Standalone theme browser (second build target)

This codebase ships **two** deployable web targets, not two packages: the admin CRM (`lib/main.dart`, Supabase + auth) and a public, unauthenticated theme browser (`lib/main_theme_browser.dart`) that the marketing site links to. The shared theme-preview module used by both is host-agnostic — it bootstraps itself and takes only a `routePath` knob for URL-syncing — so each entry point supplies just its own chrome (the admin nav rail vs. a public top bar) and both share `DesignConstants` so the catalog reads identically either way. Both targets keep the Flutter web hash URL strategy (no `usePathUrlStrategy`) so neither target's routing changes affect the other. See *Production deployment* for the build/deploy commands for both targets.

## Sibling systems in this monorepo

- `../FastApiBackend/` — the CRM's primary backend. All members / member-detail / gym-setup / billing calls go here via `ApiClient`. Contract: Pydantic schemas in `../FastApiBackend/src/<domain>/<domain>_schema.py`.
- `../Database/` — Supabase schemas, RLS, enum mirrors. `openapi.json` is an optional gitignored local convenience dump (never committed, never expected to exist).
- `../VideoService/` — the video data pipeline (scrape / scan). The CRM's video template endpoints are served by the FastApiBackend (`/api/v1/presets/templates*`), not directly by VideoService. VideoService is still the source of video data but is no longer a runtime dependency of the CRM.
- `../ThemeService/ThemeFlutter/` — the shared `theme_flutter` white-label runtime + resolvers (path dep) for the theme preview.
- `../MobileApp/` — the member-facing mobile app, which shares this app's design language. Shared widget candidates often live there too (check before building new shared widgets).
- `../LandingPage/` — React marketing site. Its `COPY` dict and `hifi/ds.jsx` design system inform admin copy/voice and the landing-aligned tokens. Read `../LandingPage/CLAUDE.md` for user-facing strings that should match marketing voice.

## Search the web for conventions before designing

When the UX question is "how do good apps usually present X?" — login flows, empty states, error states, onboarding, list/detail patterns, settings, paywalls, billing screens, password reset, etc. — **search the web first.** Look at what proven web apps actually ship (Stripe Dashboard, Linear, Notion, Vercel, Intercom admin). Don't guess.

Why: convention is a usability shortcut. Users pattern-match to flows they've seen elsewhere; a novel treatment of a normalized interaction feels wrong even when it's "creative," and guessing wastes iteration cycles when the answer is publicly documented.

How: for normalized patterns, run a WebSearch + WebFetch a few real apps before proposing a layout; reference Material 3 where it applies; quote the convention you found. Skip the search for genuinely product-specific work (this product's unique mechanic, our brand voice, internal logic).

## General Principles

**SOLID** — single responsibility, open/closed, substitutable subtypes, segregated interfaces, depend on abstractions.
**DRY** — single source of truth for each piece of logic.
**KISS** — favor simplicity over complexity.
**YAGNI** — don't add features until needed.
**Separation of Concerns** — keep UI, business logic (bloc), and data (repository) separate.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, a feature that changed the architecture), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**

- **EVERY widget MUST import and use `package:crm/core/constants/design_constants.dart`.**
- **NEVER hardcode colors** — no `Colors.red`, no inline `Color(0xFF...)`, no copy-pasted hex codes.
- **NEVER hardcode font properties** — no inline `fontFamily`, `fontSize`, or `fontWeight`. Use the text styles in `DesignConstants` (`h1`, `h2`, `h3`, `p`, `pBig`, `pSmall`, etc.).
- **NEVER hardcode spacing, padding, radius, or border widths.** Use `DesignConstants.spacing*`, `DesignConstants.padding*`, `DesignConstants.radius*`, `DesignConstants.buttonBorderSize`.
- **A token is never something you inline.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/radius/padding, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
- **`design_constants.dart` is this app's own design system and may be edited deliberately.** CRM's tokens are **landing-aligned** — they match the marketing landing page's design system (`../LandingPage/hifi/ds.jsx`) so the public theme browser reads as an extension of it: cool off-white ground (`#F3F5F8`), white lifted cards with soft layered shadows (`cardShadow` / `buttonShadow`), the sapphire accent + its `primaryGradient`, Geist (`baseFont` / `monoFont`), tight 12/8 corners with 20px object cards. It is **not** byte-for-byte identical with `../MobileApp/` — do **not** mirror token changes to it. Keep all token changes centralized in this file (so one edit reskins the whole app) and add/rename tokens only when the design genuinely needs it. See `DESIGN.md` for the system.
- **ALWAYS reference DesignConstants** for every color, text style, padding, radius, and spacing.
- **Light + dark are both live.** The **color, gradient, shadow, and text-style** tokens are *getters* that resolve through `themeController.isDark` (`lib/core/state/theme_controller.dart`), so one mode change re-skins the whole app — the two palettes sit side by side in `design_constants.dart` as private `_l*` (light) / `_d*` (dark) constants. **Consequence: those tokens are no longer `const`** — never put a `DesignConstants` color/textstyle/shadow inside a `const` constructor (drop the `const`; the analyzer is the gate). Spacing / radius / icon-size / nav-dim tokens and the fonts stay `const` / `final`. Add a *pair* of values (light + dark) when you add a color token. `onAccent` is the label color for a sapphire/gradient fill (near-white in both themes) — use it for selected pills / button labels, never a raw `surface`/`backgroundColor`. `onAccent` is only safe on a fill that is dark in **both** themes; for a *solid* `backgroundColor` whose luminance flips between themes (e.g. `okYellow` — dark amber in light, bright gold in dark), use `onFill(fill)`, which picks near-white or near-black ink by the fill's luminance (`AppPrimaryButton` does this automatically for a passed `backgroundColor`).

**Icons: Prefer Material Symbols, Material `Icons.*` allowed**

- **Default to `Symbols.*_sharp`** from `package:material_symbols_icons/symbols.dart` — the design system's primary glyph set, carrying the variable `weight` axis the look depends on. (That variable `weight` axis is exactly why prod builds must pass `--no-tree-shake-icons` — see *Production deployment*.)
- **`Icons.*` from Flutter's built-in Material icons is permitted.** The design system is its own fork and isn't locked to one icon family; `Icons.*` values are plain `IconData` and are fine to use directly — including stored on plain models.
- **Set `weight: DesignConstants.iconWeight` on `Symbols.*_sharp` icons** (it drives stroke weight). Plain `Icons.*` glyphs don't honor the weight axis, so it's a no-op there — don't bother.
- **NEVER hardcode `size:` on any `Icon()`** (either family). Use `DesignConstants.iconSize*` — `iconSizeBig` (32), `iconSizeLarge` (24), `iconSizeMedium` (20, default), `iconSizeSmall` (18), `iconSizeTiny` (16). Same Big→Tiny cadence as `spacing*`. If a size doesn't match one, snap to the nearest token or ask before adding a new one.
- Good: `Icon(Symbols.person_sharp, size: DesignConstants.iconSizeMedium, weight: DesignConstants.iconWeight)`
- Also fine: `Icon(Icons.person, size: DesignConstants.iconSizeMedium)`

**App Theme**

- `AppTheme.current` (`lib/shared/themes/app_theme.dart`) maps DesignConstants into Material 3's `ColorScheme` + `TextTheme` at the active brightness so stock Material widgets auto-theme. `main.dart` wraps `MaterialApp` in a `ListenableBuilder` on `themeController` and passes `theme: AppTheme.current`, so a mode change repaints the whole tree at once (the app never reads `Theme.of(context)` — DesignConstants is the real driver, and it's kept the single source of truth: `AppTheme.current` reflects `themeController.isDark`, never the reverse).
- For widget-specific styling beyond the global theme, reach into `DesignConstants` directly. Don't add one-off overrides at the call site.

**Light / Dark / System (per-employee, persisted)**

- The active mode lives in the global `themeController` (`ThemeController`, a `ChangeNotifier` like `selectedGym`); `DesignConstants.isDark` keys off it. `System` follows the OS — `main.dart`'s root observer feeds platform brightness in via `themeController.setPlatformBrightness`.
- **The choice persists per employee** in `gym_employees.theme_preference` (a `theme_mode` enum: `system`/`light`/`dark`). It rides along on `GET /api/v1/gyms/` (`GymWithRole.themePreference`) and the auth gate's `_activate` hydrates it at login (the **active gym's** value wins); the **Settings → Appearance** control saves changes via `PUT /api/v1/gyms/{gymId}/employees/me/theme` (`features/settings/` — `SettingsBloc` applies the theme optimistically to `themeController`, then persists and reverts on failure).
- **The standalone theme browser is light-only** (a marketing surface matching the landing page): `main_theme_browser.dart` pins `themeController` to `ThemeMode.light` and never mounts the Settings control, so every token resolves light there regardless of the visitor's OS. The `lib/showcase/` member-app preview is unaffected — it resolves the tenant brand through `ShowcaseTokens`, not `DesignConstants`.

## Dart Standards

**Imports**
- **ALWAYS use package imports** (`package:crm/...`) — never relative imports.
- Good: `import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';`
- Bad: `import '../data/repositories/members_list_repository.dart';`

**Naming**
- Files: `member_row.dart`, `members_list_repository.dart`, `member_detail_bloc.dart`.
- Classes: `MemberRow`, `MembersListRepository`, `MemberDetailBloc`.
- Functions/variables: `getMembersList`, `memberCount`.
- Constants: `kMaxItems`. Private: `_internalVar`, `_PrivateWidget`.
- Blocs: `FeatureBloc`, `FeatureEvent`, `FeatureState`.

**Formatting**
- Max 80 characters per line.
- **Hand-format. Do NOT run `dart format` / `make format` in this app.** The repo isn't format-clean, so a blanket format rewrites ~60 files — including the deliberately-forked `design_constants.dart` — and buries your actual change in churn. Match the surrounding style by hand instead.
- **`flutter analyze` (`make analyze`) is the gate, not formatting.** Keep it clean before committing.
- Trailing commas on multi-line widget trees for clean diffs.

**Type Hints**
- Always annotate function parameters and return values.
- Use `?` for nullable types. Use generics (`List<MemberRow>`, `Map<String, int>`).

## Code Complexity & File Organization

- **Prefer deep module trees over flat files** — many small files beats few big ones.
- **Aggressively extract sub-widgets and helper functions.** Each unit short and readable.
- **Extract to a separate file early.** If a widget has a distinct responsibility, give it its own file immediately.
- **Use Column/Row with `spacing:`** to structure layouts — keeps trees shallow.
- Good: A parent widget composing 3–4 named children, each in its own file.
- Bad: A single `build` method with deep nesting and inline widget construction.

**File length**
- Aim for **under ~150 lines per file**.
- One public widget per file. Private helper widgets in the same file are fine only if very small (<30 lines) and tightly coupled.

**Group related widgets into subfolders.** Avoid flat widget directories with many files:
- `presentation/sections/` — `profile_header_section.dart`, `membership_carousel.dart`, `payment_history_section.dart`, etc.
- `presentation/dialogs/` — one dialog per file (`charge_card_dialog.dart`, `freeze_account_dialog.dart`, …).
- Standalone widgets can stay flat.

Helper functions (formatters, display builders) live in their own `*_helpers.dart` / `*_format.dart` file inside the subfolder (e.g. `member_detail_format.dart`, `membership_display_helpers.dart`).

## Screen Layout & Spacing

**Horizontal padding**
- Use `DesignConstants.screenHorizontalPadding` for all screen-level horizontal padding. Visual consistency across screens is non-negotiable.

**Spacing rules**
- **NEVER use `SizedBox` for spacing.** Always use the `spacing:` parameter on `Column`/`Row`.
- **Use `DesignConstants.spacing*` constants for every spacing value.** Available: `spacingBig` (32), `spacingLarge` (16), `spacingMedium` (8), `spacingSmall` (4), `spacingTiny` (2).
- Good: `Column(spacing: DesignConstants.spacingLarge, children: [...])`
- Bad: `SizedBox(height: 16)` between Column children.
- If children need different spacing, restructure into nested Column/Row groups with uniform `spacing:` on each — do not fall back to SizedBox.
- **Exception — `ListView.separated`:** a `SizedBox` returned from its `separatorBuilder` is fine and encouraged (the rule targets one-off `SizedBox`es wedged between `Column`/`Row` children; `ListView.separated` has no `spacing:`). Keep the height on a `DesignConstants.spacing*` constant.
- **Never use `margin`** on Container/DecoratedBox for spacing between widgets — use the parent's `spacing:`.
- **Never use `Padding` to create a gap between sibling widgets** — gaps belong to the parent's `spacing:`, not to either sibling. Padding is only for the *inside* of a single widget (screen-edge containment, internal content padding). If you're adding `EdgeInsets.only(top: ...)` to make space below a previous widget, stop — that's a gap; wrap the siblings in a `Column`/`Row` with `spacing:`. For sliver layouts where you can't share a Column, combine adjacent `SliverToBoxAdapter`s into a single Column with `spacing:` rather than padding each separately.
- If a repeated spacing pattern doesn't match an existing constant, extract a helper. Do not scatter magic numbers.

## Section Structure & Gap Hierarchy

A screen is usually a stack of **Sections**. Each Section is a `Column` with a Title and its Content, using `spacing: DesignConstants.spacingLarge` between them.

The Content is itself a `Column` (or similar) with `spacing: DesignConstants.spacingMedium` between its grouped pieces (subtitles, rows, cards).

Inside those pieces, the innermost groups use `spacing: DesignConstants.spacingSmall` (or `spacingTiny`) for tightly related elements — a label and its value, icon + text, chips in a row.

**Why the cascade**: gap size communicates relationship. Elements that belong together the most get the smallest gap; unrelated things get the biggest. A Title and its Content are *less* tightly related than the items *within* the Content, so the Title→Content gap must be larger than the gaps inside the Content. The same logic applies one level down.

The default cascade as you descend is `spacingLarge → spacingMedium → spacingSmall`. This holds ~90% of the time; it is a default, not a strict rule — skip a level when the design actually calls for it.

**Split widgets at the Title/Content boundary** — the spot where the gap jumps to `spacingLarge` is also the natural boundary for a new widget *class*. A Section's `build` typically returns `Column(spacing: spacingLarge, children: [Text(title, ...), _Content(...)])` and nothing else, with `_Content` handling the medium-gap layer.

Good:
```dart
class ProfileSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge, // title -> content
      children: [
        Text('Profile', style: DesignConstants.h1),
        _ProfileContent(member: member),
      ],
    );
  }
}

class _ProfileContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium, // between content groups
      children: [
        _NameRow(member: member),       // internally: spacingSmall
        _MembershipRow(member: member), // internally: spacingSmall
        _ActionButtonsRow(),
      ],
    );
  }
}
```

Bad: one flat `Column(spacing: spacingMedium, children: [title, subtitle, row1, row2, row3])` — the title gets the same gap as unrelated rows, flattening the hierarchy.

Bad: `spacingSmall` between title and content and `spacingLarge` between rows — inverted cascade.

Bad: nesting the cascade but cramming it into one giant `build` method — the cascade reveals the split points; honor them by extracting each level into its own widget class.

## Screen Architecture

- **Screens are collections of small, focused widgets** — not monolithic build methods.
- Break screens into logical sections (`ProfileHeaderSection`, `MembershipCarousel`, `PaymentHistorySection`).
- Each section has a single, clear responsibility.

**Widget naming**
- Section widgets: `[Content]Section` — `RetentionSection`, `PersonalInfoSection`.
- Item widgets: `[Item]Card`, `[Item]Tile`, `[Item]Item`.
- Grid/List widgets: `[Content]Grid`, `[Content]List`.
- Avoid generic names like `CustomWidget`, `WidgetOne`.

**BLoC integration in widgets**
- **Widgets dispatch events to the bloc** — never call repository methods directly.
- **Widgets listen to state changes** via `BlocBuilder` / `BlocListener` / `BlocConsumer`.
- **No callbacks for business logic** — use bloc events. Callbacks are fine for simple UI interactions (a button `onTap`, a form field `onChanged`).
- Good: `context.read<MemberDetailBloc>().add(MemberActionErrorCleared())`
- Bad: passing an `onSave` business-logic callback through widget layers.

**Widget separation**
- Default to extracting into its own file. If a widget has a clear name and responsibility, it gets a file.
- **Default location is shared.** A widget belongs in `lib/features/<feature>/presentation/widgets/` only if it's specifically tied to that feature's content. Topbars, buttons, cards, list rows, tables, dialogs, dividers, info rows, badges, chips, sections — all live in `lib/shared/widgets/`. **When unsure, prefer shared.** Moving a feature widget to shared later is cheap; building two parallel versions is not.
- One public widget per file.
- **MANDATORY: check `lib/shared/widgets/` before writing a single line of new widget code.** Run `ls lib/shared/widgets/` (and `ls lib/shared/widgets/*/`) BEFORE composing widgets. If a shared widget covers the pattern (cards, buttons, headers, tables, list rows, info rows, dialogs, search boxes, filter bars, view switchers, etc.), USE IT. Do not build a parallel implementation. Pass parameters or extend the shared widget — the point of the library is that every screen looks identical because every screen uses the same primitives.
- **Tables specifically:** any table (header row + data rows + dividers + sticky-or-not + tappable-or-not) is `AppDataTable` from `lib/shared/widgets/app_data_table.dart`. Configure `AppDataTableColumn` and `AppDataTableRow` — do not handroll headers, rows, or dividers.
- **Before building a new shared widget, also check `../MobileApp/lib/shared/widgets/`.** The member app shares this design language. If a version of the pattern exists there, copy and adapt it (rewrite imports `package:mobile_app/` → `package:crm/`) rather than building from scratch. The goal is parity, not divergence.
- **If you skip this check, you will be asked to redo the work.** This has happened — a contributor built a custom table when `AppDataTable` was sitting in shared, and it had to be torn out and rewritten.

## UX Requirement: logout access

Every authenticated screen must offer a way to sign out. Authenticated screens wrap themselves in `AppShell`, which carries the sign-out path in its nav chrome — pinned to the bottom of the left `SectionsBar` rail at desktop widths, and in the hamburger dropdown (`SectionsMobileMenu`) below `navMobileBreakpoint`. Never ship an authenticated screen with no way out.

## UX Requirement: every mutation ends in a visible confirmation, never a silent dismiss

**No data-changing flow may end with just a spinner that then disappears.** Every action that mutates state — charge, refund, upgrade, reprice, cancel, freeze, end, start, mark-paid-cash, save — must resolve to an **explicit terminal state the user sees**: a success confirmation on success, or a clear error with a retry path on failure. A dialog must **never** dispatch its bloc event and immediately `Navigator.pop()` — that reads as "loading… gone" and leaves the user unsure whether it worked. This is non-negotiable for billing, where "did my card actually get charged / refunded?" ambiguity is unacceptable.

- **The shape:** select/preview → **processing** (spinner) → **success / failure** terminal step that the user dismisses. The canonical implementation is the charge-card dialog's `_ChargeStep { payer, payment, processing, success }` (`dialogs/charge_card_dialog.dart`) ending on `ChargeCardSuccessView` (a green `Symbols.check_circle_sharp` naming what happened); the cancel dialog's `_Phase { select, review, complete }` is the same shape with an outcome list.
- **Confirm against COMMITTED state, not "request sent."** Either observe a **dedicated** per-action success channel on `MemberDetailLoaded` (the monotonic-token pattern — `chargeCardSuccess`, snapshotted at open and watched via a `BlocListener`/`BlocConsumer` with `listenWhen`), or `await awaitMemberDetailSettle(bloc, tokenBefore)` (`dialogs/member_detail_bloc_settle.dart`) before showing success.
- **A dialog that owns its own processing→success step must ride a dedicated channel**, not the generic `_runMutation` `isMutating` flag — otherwise the screen-level `_MutationOverlay` spinner and `BillingErrorDialog` fire underneath/alongside it and collide with the dialog's own confirmation. (Charge-card and cancel deliberately route around the screen overlay this way; `update price`/reprice still rides the generic path and is a known gap to close when touched.)
- This is the bar for new flows **and** for any existing fire-and-pop flow you touch.

## Project Structure

```
lib/
├── main.dart                      # admin app entry — Supabase + Stripe + auth gate
├── main_theme_browser.dart        # public theme-browser entry (no auth)
├── core/
│   ├── config/                    # environment + Supabase config
│   ├── constants/                 # design_constants.dart (forked), app/env constants
│   ├── errors/                    # exceptions.dart (typed exception hierarchy)
│   ├── navigation/                # app_routes.dart
│   ├── network/                   # api_client.dart (JWT dio + 401 refresh)
│   ├── state/                     # selected_gym.dart (app-wide gym pick)
│   └── utils/                     # money.dart, validators.dart, ...
├── features/
│   └── <feature>/
│       ├── bloc/                  # CRM features: bloc + event + state
│       ├── data/
│       │   ├── models/            # json_serializable models (+ *.g.dart)
│       │   └── repositories/      # wrap ApiClient, throw typed exceptions
│       └── presentation/
│           ├── screens/
│           ├── sections/
│           ├── dialogs/
│           └── widgets/
├── shared/
│   ├── themes/app_theme.dart      # ThemeData ← DesignConstants
│   └── widgets/                   # cross-feature reusables (AppDataTable, ...)
└── showcase/                      # member-app preview screens for the live theme
                                   # preview tab (resolves branding via theme_flutter)
```

## Development Commands

- `make run` — serve the admin web app on `http://localhost:8081`.
- `make run-themes` — serve the standalone theme browser on `http://localhost:8082` (second target). Runs alongside `make run` on its own port.
- `make analyze` — static analysis. **Must be clean before committing — this is the gate.**
- `make format` — `dart format lib test`. **Avoid in this app** (see *Formatting*): it churns ~60 files including the forked `design_constants.dart`. Hand-format instead.
- `make test` — run all tests.
- `make get` — `flutter pub get`.
- `make clean` / `make reset` — clean build artifacts / clean + get.
- `make doctor` — `flutter doctor`.
- Code-gen: `dart run build_runner build --delete-conflicting-outputs` after adding/changing a `json_serializable` model.

## Code Quality

- **Always run `flutter analyze` after making code changes.** Fix every warning and error.
- **Zero warnings policy.** No deprecated APIs (use `.withValues()` instead of `.withOpacity()`, etc.).
- **Const constructors** wherever possible.
- Full null safety.
- No hardcoded values (see *Theming System*).

## Dependencies

- **Add dependencies with `flutter pub add <package>`.** Never edit `pubspec.yaml` by hand. Dev deps: `flutter pub add --dev <package>`.

**This list documents only dependencies that carry rules or scope** — what they're for and where they may (or may not) be used. A routine, self-explanatory UI utility does not need a line here; only document a dependency when its use is scoped, restricted, or architecturally significant.

Scoped / significant dependencies:
- `flutter_bloc` / `equatable` — state management for the CRM feature stack (login, gym setup, members list, member detail + billing). Events/states use `equatable`.
- `dio` — HTTP client behind `ApiClient` for the FastApiBackend (CRM data). Distinct from the `theme_flutter` transitive `dio` — this is the direct CRM dep; route every CRM call through `ApiClient`, not a raw `Dio`.
- `supabase_flutter` — auth (JWT for `ApiClient`, session refresh) and real-time DB for the CRM stack. Gated in `main.dart`; absent from the theme-browser target.
- `flutter_stripe` / `flutter_stripe_web` / `stripe_js` — Stripe payment collection: the member-detail billing dialogs, and the **kiosk signup's card step** (`features/kiosk/.../signup/kiosk_card_step.dart`), which wraps the same shared `CardFieldBox` and tokenizes with `Stripe.instance.createPaymentMethod`. The kiosk holds only the resulting `pm_…` id plus the brand/last-four — never card data, never a saved-card list, and it names the payer the card attaches to (the fresh-card law; see the `kiosk-guide` skill).
- `get_it` — service locator for DI across CRM features.
- `json_annotation` / `json_serializable` / `build_runner` — code-gen for API response models (`*.g.dart`).
- `flutter_dotenv` — loads `.env.dev` / `.env.prod` at startup for Supabase / Stripe / `API_BASE_URL` (see *Configuration*).
- `intl` — date/currency formatting. `uuid` — local UUIDs for optimistic creates. `stream_transform` — bloc stream operators (debounce/switchMap).
- `timezone` — **the Settings gym-timezone picker only** (`features/settings/.../timezone_picker_dialog.dart` + its section): the full IANA database with current UTC offsets. Initialized **lazily on first use** (memoized `ensureTimezonesInitialized`), never at app startup.
- `web` — Flutter web interop (required by `stripe_js`). Also used directly in `lib/core/utils/file_download.dart` (Blob → object URL → `<a download>` click) to trigger the browser download of a report/export zip fetched via `ApiClient.getBytes`.
- `google_fonts` — Geist (the landing typeface) via `GoogleFonts.geist()` / `GoogleFonts.geistMono()` (referenced by `DesignConstants.baseFont` / `monoFont`).
- `material_symbols_icons` — `Symbols.*_sharp` icons.
- `flutter_markdown_plus` — renders a read-only markdown prompt panel in one feature screen. Styling from `DesignConstants`. Used only there.
- `flutter_quill` / `markdown_quill` / `markdown` — **waiver text only.** The gym owner edits formatted text in the waiver editor (`features/memberships/.../waiver_editor_screen.dart` + `widgets/waiver_markdown_editor.dart`); the body is stored as a **Markdown string** (`MarkdownToDelta` to load, `DeltaToMarkdown` to save). The same `WaiverMarkdownEditor` is reused **read-only** wherever a waiver is *signed* — the shared `sign_waiver_panel.dart` at the desk and the membership flow's shared waiver panel (`features/membership_flow/presentation/widgets/flow_waiver_doc_panel.dart`), which the kiosk signup's waiver step renders — so a member and a staff member read byte-identical text. `appflowy_editor` was evaluated first but does not compile on the pinned Flutter SDK. Scoped to waiver text — don't reuse for other rich-text needs without revisiting.
- `http` — **for public, unauthenticated endpoint reads only** (no Supabase session) — the edge-integration screens mentioned in *What this app is*. Nothing else; CRM data goes through `ApiClient`.
- `theme_flutter` (path dep, `../ThemeService/ThemeFlutter`) — **for the live theme preview only**, with one narrow carve-out. The shared white-label runtime + resolvers (showcase screens live locally in `lib/showcase/`). Transitively pulls `dio`, `flutter_svg`, `get_it` — **not** a license to wire `dio` into screens outside the theme preview. The carve-out is its **celebration motion vocabulary** — `CelebrationTimings` (the durations) and `ScaleReveal` — which is a pure design-system import with no runtime behind it, shared so the kiosk's post-check-in glance celebrates in the same language the member app does rather than re-deriving curves. `lib/shared/widgets/animation/` (`CountUpText`, `StaggeredReveal`, clones of the member app's) is the app-wide home for those widgets and is used by both `lib/showcase/` and the kiosk; that, and nothing else, is what may reach into `theme_flutter` outside the preview.
- `cached_network_image` — **for `lib/showcase/` only** (backs `ShowcaseAsset.network` loading a gym's reward/class photos in the preview). Scoped to the showcase.
- `url_launcher` — **only** the standalone theme browser's top bar (Home / Pricing / Book-a-demo links).
- `image_picker` — **image upload flows only** (reward catalog images, member photos, class images). Used via `ImageUploadPickerField` — do not call `ImagePicker` directly at a call site.
- `shared_preferences` — **kiosk session persistence only** (`features/kiosk/data/kiosk_session_store.dart`): the kiosk-active flag + its runway deadline. On web this writes the same browser localStorage as the Supabase session — a deliberate *fate-share* (a flag can't outlive its session), see the `kiosk-guide` skill. Scoped to the kiosk store; don't reuse it for other persistence.
- `qr_flutter` — **the kiosk "Get the app" modal's download QR only** (`features/kiosk/presentation/widgets/get_app/kiosk_download_qr.dart`); the only real QR in the app (the kiosk home's check-in QR is still a static placeholder). Scoped to that widget; don't reuse it elsewhere. **A QR's colours are functional, not themable:** both kiosk QR tiles render through the one `KioskQrFrame` and pin to `DesignConstants.kioskQrModule` / `kioskQrQuietZone` (dark-on-white in EVERY theme). Resolving them through `text` / `surface` inverts the code under the dark theme, which many scanners fail on — never "fix" them back onto the theme tokens.

## Configuration (dual: dart-defines + dotenv)

Two config mechanisms, by design:

- **dotenv (`.env.dev` / `.env.prod`)** carries the CRM stack secrets/URLs loaded at startup via `flutter_dotenv`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`, `STRIPE_PUBLISHABLE` (keys in `lib/core/constants/env_constants.dart`; debug → `.env.dev`, release → `.env.prod`, selected in `lib/core/config/environment.dart`). Never commit real secrets; `.env.example` documents the shape.
- **dart-defines** carry the **edge integration** base URLs (compile-time `String.fromEnvironment`): `BACKEND_BASE_URL` (FastApiBackend public edge endpoints), `CUST_BASE_URL` (ThemeService), plus the theme-browser link targets `LANDING_URL` / `PRICING_URL` / `BOOK_URL`. They default to `localhost` (dev) and are overridden at build time for prod (see *Production deployment*).

## Production deployment (web)

The admin app deploys as a static build to **S3 + CloudFront** at `https://app.combatden.net` (mirrors `../LandingPage/deploy/`). See `../DEPLOYMENT.md` for the full runbook.

`web/` is CombatDen-branded (not the Flutter template): the tab `<title>`, `manifest.json`, and the favicon + PWA icons (generated from `assets/images/combatden_logo.png`) all carry the brand. `web/` is shared by both build targets, so the admin app and the theme browser get the same favicon/title.

- **Build for prod with the edge base URLs** (they override the `localhost` defaults): `make build-web` → `flutter build web --release --base-href=/ --no-tree-shake-icons --dart-define=CUST_BASE_URL=https://theme.combatden.net --dart-define=BACKEND_BASE_URL=https://api.combatden.net`, followed by `python3 deploy/prune_web_fonts.py build/web`.
- **`--no-tree-shake-icons` is required, and the font prune that follows it is not optional.** Icon tree-shaking only runs in release builds and corrupts the variable `weight` axis of `MaterialSymbolsSharp` — so every `Symbols.*_sharp` icon (the whole nav bar) renders in debug but **disappears on deploy** (flutter/flutter#183381). The flag ships the full font with its axes intact, but also ships the package's two **unused** families full (Rounded ~15 MB + Outlined ~10 MB), which Flutter web loads eagerly at startup — so `deploy/prune_web_fonts.py` deletes those two `.ttf`s and strips them from the manifest post-build (~25 MB saved; the app uses only Sharp). Both `make build-web` and `make build-themes` run flag + prune. **Don't remove either without restoring the other** — the flag alone bloats the bundle; the prune alone re-breaks icons.
- **Deploy tooling lives in `deploy/`** (boto3, its own `pyproject.toml`): `make deploy-provision` (S3 + ACM cert), `make deploy-finalize` (CloudFront — includes a 403/404 → `/index.html` SPA fallback so deep links and refresh resolve), then `make deploy` (build + upload + invalidate). DNS records are added by hand at Squarespace.
- Both backends are served over HTTPS at their own subdomains (`theme.` / `video.combatden.net`), so there is no mixed-content issue and the APIs' open CORS (`["*"]`) covers the cross-origin calls. **No Dart code changes are needed for prod** — only the dart-defines at build time.

**Second deployment — the standalone theme browser** ships from the **same project, a different `--target`**, to `https://themes.combatden.net`.

- **Build:** `make build-themes` → `flutter build web --release --base-href=/ --target lib/main_theme_browser.dart` plus the same two API dart-defines as the admin build.
- **Deploy tooling lives in `deploy-themes/`** — a copy of `deploy/` whose `config.py` points at bucket `combatden-themes` / domain `themes.combatden.net`. Config-driven and otherwise identical: `make deploy-themes-provision` / `-finalize` / `deploy-themes`.
- Both targets emit to `build/web`, so the admin and themes deploys are **sequential, never simultaneous** (build admin → `deploy`; build themes → `deploy-themes`).

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
