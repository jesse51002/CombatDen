# MobileApp — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this app is

This is the CombatDen **member-facing mobile app** — the Flutter client a gym's
members hold in their pocket. It is **live software**: real Supabase auth, real
FastApiBackend member-portal data over `dio`, Bloc state management, a
per-member identity resolved at boot, and per-gym theme hydration. When the app
went live the **look and design of the existing screens did not change** — real
member data went live *under* them.

- **Native Flutter app** (Android + iOS). Not a web target. The QR check-in
  scanner needs camera permission (`CAMERA` / `NSCameraUsageDescription`); the
  manifest also declares `INTERNET`.
- **White-label / templated.** One codebase reskinned per tenant at runtime (see
  *Theming System*). At boot the app themes to the bundled default, then — once a
  member is selected — re-hydrates to that member's gym branding.
- **Feature-first architecture** (see *Project Structure*): each feature owns its
  `bloc/`, `data/` (models + repositories), and `presentation/` (screens +
  widgets).
- **The backend is the member portal.** Every live call goes to FastApiBackend's
  `/api/v1/member/...` surface — the contract source is
  `../FastApiBackend/src/member_portal/` (see *Repository pattern + ApiClient*).
  Those routes are gated by `verify_member_self`: a member reads only their own
  data. **By backend design the app can NEVER** write its own attendance /
  check-in, sign waivers, manage billing / cards / cancellation, or edit its
  email — those are staff-only in the CRM. Don't try to build them here; the
  routes don't exist.

**Theme/design rules are not relaxed for any reason.** See *Theming System*.

**Impeccable before UI/visual changes.** Before any non-trivial UI/visual change
here, run the `impeccable` design pass first — ideally in a dedicated Opus
subagent so it can focus. A small, unambiguous tweak (a copy fix, a single-token
correction, wiring an already-designed component) can be done directly; anything
with visual ambiguity or non-trivial size goes through `impeccable`. See the
codebase-root `CLAUDE.md` for the full rule.

## A few superseded files are kept DORMANT for the capture harness — don't flag them as dead code

Going live retired the old visual-prototype scaffolding. Most of it was removed;
what REMAINS dormant on disk is kept alive **only because the dev-only
landing-page capture harness (`tools/capture/`) still imports it** — the harness
needs its own update before these can go (see the capture warning under
*Project Structure*). So the *Always delete dead code* law below is **suspended
for this specific capture-coupled set only** — do not flag these as violations
or delete them until the capture harness is reworked or retired. The dormant,
capture-coupled set:

- The **VideoService-era read path**: `core/selected_gym.dart` +
  `core/video_service_config.dart`, `features/gym/data/gym_api_client.dart` /
  `gym_detail.dart` / `gym_repository.dart`, and
  `features/videos/data/video_api_client.dart` / `video.dart` /
  `video_feed_repository.dart` / `video_helpers.dart` / `video_selectors.dart`.
  The app reads everything through the member portal now; the capture harness
  still renders via this old path.
- `features/home/data/mock_gym.dart` + `features/stats/data/mock_stats.dart` —
  the two prototype mocks the harness still renders (topbar chrome, the
  `StreakBody` / `WinsBody` demo stats).
- `features/stats/presentation/widgets/wins/` (`wins_body` + `wins_tile` +
  `wins_tile_row`) — the post-class wins widgets, dropped from the celebration
  flow but still rendered by the harness. The wins **screen** + route are gone.
- `features/style_select/data/gyms_pager.dart` — the old VideoService gym-browser
  pager the harness pages to pick a gym/theme. The style-select **screen** +
  route are gone.

Once the capture harness is reworked or retired, this set goes with it and this
note is deleted.

## State-management model

- **Screen → Bloc → Repository → ApiClient → backend. Never skip a layer.** Every
  live feature is a `flutter_bloc` + `equatable` vertical: widgets dispatch events
  and read state via `BlocBuilder` / `BlocListener` / `BlocConsumer`; a repository
  sits behind the bloc and is never called directly from a widget; the repository
  wraps `ApiClient`. This is the standard for all feature work.
- **Bloc state is ONE Equatable class + status enums + `copyWith` (the default
  for new features).** A single immutable state class carries a `status` enum
  (`initial` / `loading` / `loaded` / `error`, plus per-action **monotonic success
  tokens** where a mutation needs a visible confirmation), rather than a class
  union of separate state types. `MemberProfileBloc`, `HomeBloc`, `RewardsBloc`,
  etc. all follow this shape.
  - **`LoginBloc` is the one class-union exception** — it was ported faithfully
    from the CRM's `LoginBloc` (state subclasses: `LoginInitial` /
    `LoginAuthenticated` / `LoginUnauthenticated` / `LoginLoading` /
    `LoginAwaitingEmailConfirmation` / `LoginError`). Both styles therefore exist
    in the tree; **single-class-state is the default for anything new** — only
    the auth vertical keeps the union because it's a straight CRM port.
- **DI is manual constructor injection — there is NO `get_it` in app code.**
  Repositories and blocs are constructed inline at their `RepositoryProvider` /
  `BlocProvider` `create:` sites (`MemberProfileRepository(apiClient: ApiClient())`,
  etc.). `get_it` is only a *transitive* dependency of `theme_flutter` (its
  internal locator); nothing in `lib/` uses it. Do not introduce a service locator.
- **One shared profile source.** `MemberProfileBloc` (`features/profile/bloc/`) is
  provided **once** above the app shell's nested navigator (in `app_shell.dart`),
  so the topbar streak/points, the rank block, and every feature that needs
  retention data read the **same** profile. Refetch it (silent
  `MemberProfileRefreshRequested`) on reserve/cancel, redeem, the celebration, app
  foreground, and a member switch. Never spin up a second profile fetch.
- **Everything resets on a member switch.** `app_shell.dart` re-keys its whole
  subtree on `ThemeRuntime.activeDesignId` + `selectedMember.memberId`, so
  switching profiles re-inflates a fresh `MemberProfileBloc` and a fresh Home,
  resetting every feature bloc.

## Repository pattern + ApiClient (the member-portal backend path)

- **All backend calls go through `ApiClient`** (`lib/core/network/api_client.dart`,
  ported from the CRM). It wraps a single configured `dio` instance with a 30s
  timeout and an `_AuthInterceptor` that:
  - attaches the **Supabase JWT** (`currentSession.accessToken`, read fresh) as a
    Bearer token on **every** request;
  - on a **401**, refreshes the Supabase session under a bounded **10s** timeout
    and retries the request **once**; if the refresh returns no token, times out,
    or throws, it calls the static `ApiClient.onUnauthorized` (wired in
    `main.dart` to sign out), dropping the app back to the login screen. The
    refresh timeout is essential — gotrue treats a host-unreachable refresh as
    *retryable* and would otherwise hang the request (and the boot-time identity
    fetch) forever.
  - **A 403 is NOT a session problem** — it maps to `ForbiddenException` (a
    friendlier "your role may have changed" message) and **never** signs the user
    out. The 401 refresh/retry path is untouched by it.
  - Timeouts / connection errors map to `NetworkException`; other error bodies to
    `ServerException` (carrying the FastAPI `detail` string when present).
- **The base URL is rewritten for the Android emulator.** `ApiClient` resolves
  `API_BASE_URL` through `EnvironmentConfig.url(...)`
  (`lib/core/config/environment.dart`), which rewrites a `localhost` / `127.0.0.1`
  host to `10.0.2.2` on Android only (the emulator can't see the host's loopback);
  a real domain and web/iOS/desktop are untouched.
- **Repositories wrap `ApiClient`.** Each feature's `data/repositories/` exposes
  domain methods (`getMyMembers`, `getProfile`, `getSchedule`, `reserve`,
  `listRewards`, …), takes an `ApiClient` in its constructor, converts JSON to
  models, and throws the typed exceptions. Blocs depend on repositories, never on
  `ApiClient` directly.
- **Read the Pydantic schema before calling any endpoint.** The authoritative
  request/response contract for the member surface lives in
  `../FastApiBackend/src/member_portal/schema/member_portal_schema.py` (and the
  domain schemas it reuses — classes, rewards, billing, videos). Match the path,
  method, and every field listed under `required`; the model `fromJson` must track
  the response shape exactly. When the contract changes, update the model in the
  same change. (`../Database/openapi.json` is an optional gitignored local dump —
  never committed, never expected to exist.)

## Models & code generation

- **Models are `json_serializable` with `snake` field renaming.** Each model
  declares `@JsonSerializable(fieldRename: FieldRename.snake)` (add
  `createToJson: false` for read-only response models) and a generated `*.g.dart`
  part committed alongside it. Regenerate with
  `dart run build_runner build --delete-conflicting-outputs`; never hand-edit a
  `*.g.dart`.
- **Every model's doc comment names the Pydantic schema it mirrors** — e.g.
  `MemberIdentity` says it mirrors `MemberPortalIdentity` in
  `member_portal_schema.py`. Keep that pointer accurate; it's how the next reader
  finds the contract.
- **Resilient enum parsing.** Any enum parsed from JSON must have a safe fallback
  in its `fromJson` — `firstWhere(..., orElse: () => <default>)`. Status-like
  enums get an `unknown` variant; view-like enums fall back to a sensible default.
  Every `switch` on such an enum must handle the fallback.
- **Backend string display.** The API hands us lowercase strings (`'active'`,
  `'recurring'`) — capitalize them at the render layer before display.
- **DateTime.** Render occurrence times **gym-local, verbatim** as the backend
  sends them; sign-up / cancel echo the occurrence's ORIGINAL slot
  (`class_id, occurrence_date, occurrence_time`) — a cancel passes them as query
  params on the `DELETE`.

## Authentication & identity

- **Supabase is auth ONLY (GoTrue).** The mobile client holds no DB privileges —
  Supabase gives us the session/JWT and nothing else; all data is the
  FastApiBackend member portal. `main.dart` boots Supabase best-effort
  (`SupabaseConfig.initialize`, logged-and-degraded on failure), initializes
  `ThemeRuntime` on the bundled default, wires `ApiClient.onUnauthorized`, and
  mounts the `AuthGate` under the one app-lifetime `LoginBloc`.
- **`AuthGate` → `MemberGate` → `AppShell`** (`features/login/presentation/`):
  - `AuthGate` routes on `LoginBloc` state — a boot splash on `LoginInitial`, the
    login/register/verify flow while unauthenticated, and the `MemberGate` once
    authenticated. `LoginBloc` detects an **external session** (persisted session
    on boot, the email-confirmation link landing, a token refresh) and flips the
    app authenticated; it also carries a dev **auto-login** (`DEV_AUTOLOGIN_EMAIL`
    / `DEV_AUTOLOGIN_PASSWORD` dart-defines) for QA.
  - `MemberGate` resolves the member **identity** once per session and runs the
    **revalidation ladder**, then mounts `AppShell` (a nested `Navigator` over the
    shared route table, with the app-wide `MemberProfileBloc` provided above it
    and `AppLifecycleRefresh` hosting the app-open celebration check).
- **`SelectedMember` is the app-wide identity** (`lib/core/state/selected_member.dart`)
  — a plain global `ChangeNotifier` (mirroring the CRM's `SelectedGym`), **not** a
  state framework, persisted via `shared_preferences`. One verified email
  legitimately matches **several** member rows (a family shares an inbox), so the
  member is chosen explicitly and never derived from the JWT; the chosen
  `memberId` + `gymId` scope every gym-scoped member call.
- **The boot revalidation ladder** (`features/member_select/logic/`, a pure
  function over the fresh `GET /api/v1/member/members` list): a persisted member
  still in the list **restores** silently; otherwise **1 row auto-selects**, **2+
  show the picker** ("Who's training?"), and **0 shows the no-membership state**
  (a designed screen — signup is open, so an unknown email is reachable). An
  **offline** identity fetch boots read-degraded from the cached `SelectedMember`
  (+ an offline banner + retry), or shows the offline screen when nothing is
  cached.
- **The topbar is the identity surface — as an avatar in the trailing flank.**
  The topbar's grammar is a **centred brand block between single-glyph
  controls** (the back chevron on the leading edge), so identity is a glyph
  too: `TopbarIdentityAvatar`
  (`shared/widgets/topbar/topbar_identity_avatar.dart`) renders the member's
  avatar at `iconSizeXl` with a hairline `divider` ring in a 48pt tap target,
  aligned `centerRight` in `nameOnly` mode and `topRight` in `bigLogo` (so it
  doesn't float against the 100pt logo). **No chevron on it** — an avatar is
  already the learned tap target. The gym title stays **pure, uninterrupted
  brand**: no second line, no glyph inside it. Every topbar wrapper passes
  `memberName` / `memberPhotoUrl` / `memberFirstName` / `memberLastName` from
  `selectedMember`; a missing name or photo falls back to initials and then to
  the person glyph, so the avatar **never disappears** (sign-out lives behind
  it). Tapping it opens the **identity sheet** (below); the gym title's own tap
  (`AppRoutes.memberSelect` → `SwitchProfileScreen`) and `onTitleDoubleTap`
  stay wired as the secondary path.
- **The topbar's info bar shows the member's REAL belt.** Under the header,
  `InfoBar` (`shared/widgets/topbar/info_bar.dart`) renders rank / streak /
  points / QR. Its belt tile resolves in this order: the member's own rank art
  (`MemberProfile.rank?.imageUrl` — already the sub-rank override over the main
  rank's image, resolved server-side) via `CachedNetworkImageProvider`, then the
  themed `CombatDenSlots.rankBelt` slot, then the bundled `rankBadgeAsset`. All
  five topbar wrappers (home / profile / rewards / videos / class-detail) pass
  `rankImageUrl: state.profile?.rank?.imageUrl` from the shared
  `MemberProfileBloc`; the param is optional, so a bar built without a profile
  (the class-detail `live: false` path) simply keeps the themed belt. Same idiom
  as `RankHeader._Belt` / `NextRankBadge._Belt` on the profile — don't invent a
  third. **A failed load falls back, it does NOT collapse:** the belt is
  permanent topbar chrome, so the network `Image`'s `errorBuilder` returns the
  themed belt (an empty gap in the info bar would read as broken). This is the
  deliberate exception to the omit-on-missing rule the creator avatar and the
  picker's gym-logo tile follow — those are optional adornments; this is chrome.
- **The identity sheet is the account surface** (`features/member_select/
  presentation/widgets/identity_sheet.dart`, the app's first modal bottom sheet
  — every sheet goes through `shared/widgets/sheets/app_bottom_sheet.dart`,
  which borrows `SignOutDialog`'s surface tokens). One surface answers all
  three account questions: the **current member** (avatar + name + gym line +
  the signed-in Supabase email, because one email legitimately maps to several
  profiles), the **other profiles** as `MemberRow`s under a "Switch profile"
  subtitle (the current member excluded; with exactly one profile the section
  and its divider are omitted entirely — never an empty list or a disabled
  row), and **sign out**. The sheet opens INSTANTLY off the cached
  `selectedMember` — only the list area loads (placeholder blocks, not a
  spinner), and a failed re-fetch replaces **only** that area with a retry, so
  the header, the email and sign-out stay usable offline.
- **The picker row identifies the gym, not just the person**
  (`features/member_select/presentation/widgets/member_row.dart`): the member's
  avatar + name over a gym line of logo tile + gym name. The same row is the
  switch row inside the identity sheet. Both halves are shared, single
  implementations — `shared/widgets/member_avatar.dart` (`MemberAvatar`, sized
  by the caller: 48 in a row, `iconSizeXl` in the topbar; photo → initials on
  `primaryCard` → person glyph) and `shared/widgets/gym_line.dart` (`GymLine`).
  **Never fork a second avatar or gym line** — the identity mark has to read as
  the same object everywhere. A null/empty/failing `gym_logo_url` **omits the
  tile entirely** — no placeholder square (identical placeholders on every row
  add noise and disambiguate nothing).
- **One in-app switch path.** `applyMemberSelection(...)`
  (`features/member_select/logic/apply_member_selection.dart`) is the ONE
  in-app switch: select → `GymThemeHydration().applyForGym` → reset to a fresh
  home. Both `SwitchProfileScreen._onSelected` and the identity sheet call it,
  so they can never drift. It takes the `NavigatorState` (captured BEFORE the
  first await) rather than a `BuildContext`, because `AppShell` re-keys on the
  new member id and the caller is often already gone. `MemberGate.
  _selectAndHydrate` is the boot-time counterpart and must stay field-for-field
  identical: every field on `MemberIdentity` (including `gymAddress`, which
  feeds class-detail "Open in Maps") goes through both, or an in-app switch
  silently drops data a boot-time selection keeps.
- **Sign-out lives in the identity sheet, and NOWHERE else.** The profile /
  rank screen is the **retention** surface (rank, streak, progress) — an
  account-exit action has no business sitting beside a member's streak, so it
  belongs on the account surface behind the avatar. In the sheet it is a single
  full-width **row**, not a button: no fill, no border, **no red**, the only
  unfilled uncarded item, isolated below a divider at the extreme bottom —
  subordinate by isolation and position rather than alarm colour. The sequence
  is **dismiss the sheet FIRST**, then the shared `SignOutDialog` (bound to the
  HOST context, with the `LoginBloc` captured before the await); red appears
  only on that confirmation. Confirming dispatches `LoginSignOutRequested`,
  unmounting `MemberGate`, which resets `SelectedMember` and the theme to
  default so a re-login never shows the previous member's brand. Don't
  duplicate that teardown at the call site.

## Theme hydration

Branding is resolved in two stages. At boot the app themes to the bundled default
(`AppConfig.designId`, the boot/fallback preset — no member is selected yet). Once
a member is chosen, `GymThemeHydration` (`features/gym/theme_hydration.dart`)
fetches `GET /api/v1/gyms/{gym_id}/showcase`, reads its `theme_design_id`, and
calls `ThemeRuntime.selectDesign(designId)` — the engine fetches the design by id,
adopts it, disk-caches it, and fires `ThemeRuntime.changes` so the app re-themes
live. A null/empty id or any failure (offline, unresolvable design) leaves the
current/bundled theme in place — logged, never thrown, so hydration can never
block boot. `GymThemeHydration.reset()` re-selects the bundled default on
sign-out. (The showcase read is gated backend-side by
`verify_gym_member_or_employee` — any member of the gym may read its branding; see
the `employees-guide` skill.)

## Error handling

Typed exceptions live in `lib/core/errors/exceptions.dart`:
- **`NetworkException`** — timeout / connection failure (the gate treats this as
  offline).
- **`ServerException`** — a backend error response; carries `statusCode`, the
  FastAPI `detail` string (when `detail` is a plain string), and the raw decoded
  `data` (for a structured `detail`).
- **`ForbiddenException`** — a `403`, a subtype of `ServerException` so existing
  `on ServerException` handlers still catch it; catch it first to show the
  role-specific message. **Never signs the user out** (that's the 401 path).

Repositories **throw + describe**; blocs **log + handle** and surface a
user-friendly message. Every bloc-backed screen renders explicit loading / loaded
/ error states with a retry path.

## Live-session rules

These came from an adversarial review of running the app as a real member; treat
them as mandatory:

- **Celebration watermark.** The post-class celebration fires from a per-member
  watermark (`celebration_watermark_<member_id>`) checked on app open/foreground.
  A null watermark seeds **silently** (no replay storm on first run / reinstall /
  member switch); it fires **once** for the newest unseen attendance and advances
  only after the flow completes. The old "wins" card is removed from the flow (the
  screen file is dormant).
- **Refresh, no polling.** Pull-to-refresh (home / rewards / videos / profile) +
  refetch-on-tab-focus; a foreground return drives the profile refetch and the
  celebration check. No timers.
- **No placeholder creator avatars.** The served video feed carries no
  `channel_avatar_url` today — the field arrives as an **empty string**, not
  null. Every video card therefore resolves it through the one shared rule,
  `creatorAvatarProvider` (`shared/widgets/video_recc_card/creator_avatar.dart`),
  which returns null for a null/empty/whitespace URL; the card then **omits the
  `CreatorAvatar` entirely** — no placeholder circle, no ring, no reserved gap
  (the avatar-to-text gap lives on the parent `Row`'s `spacing:`, so it
  disappears with the avatar). When a real URL is present the avatar renders as
  before. Same law as the picker's missing gym logo above; never re-express the
  emptiness check at a call site. (The topbar's rank belt is the one deliberate
  exception — permanent chrome, so it falls back instead of collapsing; see
  *The topbar's info bar shows the member's REAL belt* above.)
- **Reset on switch.** Changing `SelectedMember` resets and reloads every
  feature bloc (via the `app_shell` re-key) — no stale data bleeds across profiles.

## QR check-in (a seam, not the real contract)

`features/qr_checkin/` is the topbar tile → `mobile_scanner` camera → pick today's
class → confirm → a quick streak count-up (the count-up segment of the celebration
animation, auto-dismissing). **The scanned payload is NOT parsed** and the confirm
is **stub-success** — no check-in endpoint exists for a member (by design; a member
can't self-check-in). `CheckinConfirmArgs` carries only the class name + points and
is the **seam for kiosk Phase G**: the real backend `src/kiosk/` nonce contract
(scan → staff-gated check-in → streak + points in the response) will flow through
these same screens once it lands. Don't wire a real member check-in here.

## Videos open on YouTube (there is no in-app player)

Every video surface — the videos tab's hero + carousels, a genre's full list,
the profile's "Videos to level up" carousel, and the post-booking
recommendation's "Watch" — hands the video to the OS through the one shared
helper `features/videos/presentation/widgets/video_link_helpers.dart`
(`videoUriFor` → `launchVideoFor` → `openVideoFor`). Never build a second
launch path or an in-app player.

- **The URI**: the card's own `url` when it's present and has a scheme,
  otherwise `https://www.youtube.com/watch?v=<video_id>` built from the
  card's `videoId`. A card with neither never launches (and never crashes).
- **The mode is always `LaunchMode.externalApplication`** so the YouTube app
  takes it when installed. This needs the manifest `<queries>` `https` VIEW
  intent (see `url_launcher` under *Dependencies*).
- **A failed launch is visible**: `openVideoFor` captures the
  `ScaffoldMessenger` **before** the await and shows a SnackBar when nothing
  handled the intent — never a dead tap.
- **The rec screen records, then launches, then closes.** "Watch" dispatches
  `VideoRecOpened` first (the bloc fire-and-forgets the click, so it can't
  delay the launch), then launches, and pops **only on success** — a failed
  launch keeps the recommendation on screen to retry instead of dropping the
  member out of the flow with nothing.
- **Video thumbnails are square.** `VideoReccCard`'s `roundThumbnail`
  defaults to **false**: YouTube burns caption text to the thumbnail edge and
  a `radiusBig` corner clips it. The compact carousel card is the deliberate
  exception — its thumbnail has no radius of its own; it inherits the card
  frame's `radiusSmall` clip, which is the card surface, not the thumbnail.

## Search the web for conventions before designing

When the UX question is "how do good apps usually present X?" — login flows, empty states, error states, onboarding, pull-to-refresh, list/detail patterns, settings screens, paywalls, billing screens, permission prompts, password reset, account deletion, etc. — **search the web first.** Look at what proven mobile apps actually ship (Stripe, Linear, Notion, Cash App, Robinhood, Airbnb, etc.). Don't guess.

Why: convention is a usability shortcut. Users pattern-match to flows and components they've seen in other apps. Inventing a novel treatment for a normalized interaction makes the app feel wrong even if it's "creative." Worse, guessing at conventions wastes iteration cycles when the right answer is already publicly documented.

How to apply:
- For normalized patterns, run a WebSearch + WebFetch a few real apps' screenshots before proposing a layout.
- Reference platform guidelines (Apple HIG, Material 3) when applicable.
- Quote the convention you found ("Stripe Dashboard handles empty state with X; Linear uses Y for confirmation dialogs").
- Skip the search for genuinely product-specific work (this product's unique mechanic, our brand voice, internal logic).

## General Principles

**SOLID** — single responsibility, open/closed, substitutable subtypes, segregated interfaces, depend on abstractions.
**DRY** — single source of truth for each piece of logic.
**KISS** — favor simplicity over complexity.
**YAGNI** — don't add features until needed.
**Separation of Concerns** — keep UI, business logic (bloc), and data (repository) separate.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new live backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, a feature that changed the architecture), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Always delete dead code

*(Temporarily suspended for the one dormant batch above — that batch awaits a
consolidated removal approval. Everything else: this rule is in force.)*

When something is removed, **remove it completely** — don't leave orphans behind.

When you delete a screen, widget, mock model, route, asset, enum, field, or feature, also delete:
- Every file that only existed to support it (sub-widgets, helpers, `mock_*.dart`, the whole feature folder if nothing in it survives).
- Every import, reference, route entry, and registration in `main.dart`, `app_routes.dart`, the bottom nav's route map, `pubspec.yaml`'s asset list, etc.
- Every field on a model that was only there to feed the deleted UI.
- Every asset under `assets/images/` that nothing references anymore.

Before declaring the removal done, **verify**:
- `grep -rn '<RemovedSymbolName>' lib/` returns nothing.
- `flutter analyze` is clean (no unused-import / unused-field / unused-variable warnings).
- `grep -rn '<deleted_asset_filename>' lib/ pubspec.yaml` returns nothing.

**No tombstones.** Never leave behind:
- Commented-out code or `// removed: ...` markers.
- Empty files, empty folders, or stub classes that no longer do anything.
- Re-exports / barrel files that only existed to forward the deleted symbol.
- Unused imports, unused enum variants, unused mock fields.
- Routes that point at a `NotYetBuiltScreen` placeholder for something that was deliberately deleted (delete the route too).

If unsure whether something is truly dead, grep for it. If it has zero references, delete it in the same change as the thing that made it dead — not "later."

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**

- **EVERY widget MUST import and use `package:mobile_app/core/design_constants.dart`.**
- **NEVER hardcode colors** — no `Colors.red`, no inline `Color(0xFF...)`.
- **NEVER hardcode font properties** — no inline `fontFamily`, no inline `fontSize`, no inline `fontWeight`. Use the text styles in `DesignConstants` (`h1`, `h2`, `h3`, `p`, `pBig`, `pSmall`, etc.).
- **NEVER hardcode spacing, padding, radius, border widths, divider thickness, or icon sizes.** Use `DesignConstants.spacing*`, `DesignConstants.padding*`, `DesignConstants.radius*`, `DesignConstants.buttonBorder` / `buttonBorderSize`, `DesignConstants.dividerThickness`, and `DesignConstants.iconSize{Xs|Sm|Md|Lg|Xl|2xl}` (T-shirt scale, 16/20/24/28/32/36).
- **Image dimensions ARE allowed inline.** `Image.asset(width:, height:)`, asset-bound `SizedBox` constraints, and layout `aspectRatio:` are per-asset values — they're not fungible design tokens, and there is no `imageSize*` catalog. Type the literal pixel value (or hoist it to a private `_kFoo` const at the top of the file when reused). Same for one-off `Positioned(left:/top:/...)` math when laying out an image overlay.
- **`_kFoo` private file-scoped constants are also allowed for scroll-position math, sliver / pinned-header heights, and pure layout arithmetic that has no `DesignConstants` equivalent.** Examples: `_kTopbarHeight = 268`, `_kDateRowHeight = 50`, `_kCardWidth = 258`. The carve-out is for *layout math that is intrinsically per-screen and not a fungible design token*. If the same number appears across multiple screens or controls, it's not a `_k` candidate — escalate to add a `DesignConstants` token instead.
- **Live data is NOT a license to inline values.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/padding/radius/border/divider/icon-size, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
- **`design_constants.dart` is runtime-driven, not immutable.** The brand colours (`primaryColor`, `backgroundColor`, `text`, `accent`) are static getters that resolve live from the loaded tenant customization via `BrandColor.color(slot, fallback: <const CombatDen default>)`. Derived shades (`primaryColor50/25/10`, `darkPrimary`, `text2nd/3rd`, `card`, `popup`, `divider`) are getters off those bases. Status/semantic colours (`goodGreen`, `okYellow`, `badRed`, `hyperlink`, the `*Dark` variants) stay hardcoded and are NOT brandable. The const fallback is the CombatDen palette, used verbatim when no customization is loaded. Do not hand-edit token values or the `BrandColor` wiring, and do not add/rename tokens without explicit permission.
- The customization **engine** (the shared `theme_flutter` package, imported as `package:theme_flutter/...`) is app-agnostic: it fetches the tenant's resolved customization at startup, disk-caches the last-good copy, and warns LOUDLY in the logs (never throws) if a slot the app declared in `lib/core/app_slots.dart` (`CombatDenSlots`) is missing. The engine was extracted from this app's old `lib/customization/` so CRM can share it for the live theme preview; this app injects its `CombatDenSlots` manifest + `AppConfig` into `ThemeRuntime.initialize`. The old `Brand`/`BrandScope` enum + bjj demo were **deleted** — per-tenant variation now comes from the engine, not a compile-time enum. (`design_constants.dart` is runtime-driven from the engine; this app is the customization host.)
- Images: the `BrandImage` widget is URL-first — a bundled-asset filename that maps to a customization slot renders the fetched image (disk-cached via `cached_network_image`) and falls back to the bundled asset otherwise. Call sites are unchanged.
- **ALWAYS reference DesignConstants** for every color, every text style, every padding, every radius, every spacing.

**Icons: Use Material Symbols**

- **ALWAYS use `Symbols.*_sharp`** from `package:material_symbols_icons/symbols.dart`.
- **NEVER use `Icons.*`** from Flutter's built-in Material icons.
- **ALWAYS set `weight: DesignConstants.iconWeight`** on every `Icon()` widget.
- **ALWAYS set `size:` to a `DesignConstants.iconSize*` token** — `iconSizeXs` (16), `iconSizeSm` (20), `iconSizeMd` (24), `iconSizeLg` (28), `iconSizeXl` (32), `iconSize2xl` (36). If the design lands between sizes, round to the nearest token rather than inlining a literal.
- Good: `Icon(Symbols.person_sharp, weight: DesignConstants.iconWeight, size: DesignConstants.iconSizeMd)`
- Bad: `Icon(Icons.person)` / `Icon(..., size: 21)`

**App Theme**

- Global `ThemeData` lives in `lib/shared/themes/app_theme.dart` and is wired in `main.dart`. It maps DesignConstants into Material 3's `ColorScheme` and `TextTheme` so stock Material widgets (`ElevatedButton`, `Text`, `Scaffold`, etc.) auto-theme. `main.dart` rebuilds it on `ThemeRuntime.changes` so a live re-theme repaints stock chrome.
- For widget-specific styling beyond what the global theme provides, reach into `DesignConstants` directly. Don't add one-off overrides at the call site.

## Current ThemeConfig Preset (where the live look comes from)

The colours, images, and design direction the app shows at runtime are **not**
the CombatDen dark defaults in `design_constants.dart` — those are only the
fallback used when no customization is loaded. This is a **white-label /
templated app**: the live look comes from a customization preset produced by
the ThemeService. There is no single canonical palette; never assume
or hardcode one. The customization surface is **open-ended and growing** —
colours and images are just the start; over time more of the app (copy,
layout, enabled features) becomes tenant-customizable. Build accordingly:
do not bake in assumptions that only colour and image vary.

- **`lib/core/app_config.dart` declares the BOOT/fallback preset** —
  `AppConfig.appId` (tenant, e.g. `combatden`) and `AppConfig.designId` (the
  preset the runtime initializes on so the login/gate screens paint branded
  before a member is chosen). It is **not** the live gym theme: once a member is
  selected, the live look comes from that member's gym via *Theme hydration*
  above (`theme_design_id` → `ThemeRuntime.selectDesign`), and `AppConfig.designId`
  is only the fallback/reset design. **Read `app_config.dart` first** to learn
  what the boot default is.
- **A preset lives in `../ThemeService/apps/<appId>/<designId>/`.**
  Before diagnosing or changing anything about how a preset looks, read:
  - `customization.yaml` — the design brief: `design_direction` (name +
    intent, e.g. "Duck Groove") and `colors_direction`, whose
    **`colors_direction.mode`** (`light`/`dark`) says whether the preset is
    *intentionally* light or dark.
  - `output.yaml` — the resolved output the app consumes: the four colour
    slots (`primary`, `background`, `text`, `accent`), plus every generated
    image and its prompt.
  - `final_images/` — the resolved bitmap assets (logo, belt, sparkles).
- **Never assume the dark CombatDen palette.** Always resolve the active
  preset via `app_config.dart` (the boot default) or the hydrated gym design,
  then read that preset's `customization.yaml` + `output.yaml`. A light preset
  (`color_set.mode: light`) is a deliberate, supported configuration, not a bug.
- The app maps only those four slots through `BrandColor` / `CombatDenSlots`.
  Elevated surfaces (`card`, `popup`) are a translucent **white** overlay
  whose alpha tracks the background's HSL lightness, so they self-adjust to
  any preset and stack for layered surfaces. `divider` is keyed to `text`
  (a separating line needs contrast against the surface, not elevation).
  Material's discrete light/dark `ColorScheme` is driven by
  `DesignConstants.isLightCanvas`, which resolves from the loaded
  customization's `color_set.mode` (defaulting to dark when none is loaded).

## Dart Standards

**Imports**
- **ALWAYS use package imports** (`package:mobile_app/...`) — never relative imports.
- Good: `import 'package:mobile_app/features/member_select/data/models/member_identity.dart';`
- Bad: `import '../data/models/member_identity.dart';`

**Naming**
- Files: `member_row.dart`, `member_portal_repository.dart`, `member_profile_bloc.dart`.
- Classes: `MemberRow`, `MemberPortalRepository`, `MemberProfileBloc`.
- Functions/variables: `getMyMembers`, `memberCount`.
- Constants: `kMaxItems`.
- Private: `_internalVar`, `_PrivateWidget`.
- Blocs: `FeatureBloc`, `FeatureEvent`, `FeatureState`.

**Formatting**
- Max 80 characters per line **for body code**. Package imports are exempt — Dart's formatter doesn't break import lines, and renaming folders to fit a column limit isn't worth it.
- **Hand-format additions; `flutter analyze` is the gate.** The repo is not `dart format`-clean — a blanket format churns ~60 unrelated files including `design_constants.dart`. Match the surrounding style by hand; keep `flutter analyze` clean before committing.
- Trailing commas on multi-line widget trees for clean diffs.

**Type Hints**
- Always annotate function parameters and return values.
- Use `?` for nullable types. Use generics (`List<MemberIdentity>`, `Map<String, int>`).

**Resilient Enum Parsing**
- Any enum parsed from JSON must have a fallback in its `fromJson` using `firstWhere(..., orElse: ...)` so a new backend enum value never crashes the UI. Status-like enums carry an `unknown` (or equivalent default) variant; every `switch` handles the fallback.

**Backend String Display**
- The API hands us lowercase strings (`'recurring'`, `'active'`) — capitalize them at the render layer before displaying.

## Code Complexity & File Organization

- **Prefer deep module trees over flat files** — many small files beats few big ones.
- **Aggressively extract sub-widgets and helper functions.** Each unit short and readable.
- **Extract to a separate file early.** If a widget has a distinct responsibility, give it its own file immediately. Don't wait for it to get "big enough."
- **Use Column/Row with `spacing:`** to structure layouts — keeps trees shallow.
- Good: A parent widget composing 3–4 named children, each in its own file.
- Bad: A single `build` method with deep nesting and inline widget construction.

**File length**
- Aim for **under ~150 lines per file**.
- One public widget per file. Private helper widgets in the same file are fine only if very small (<30 lines) and tightly coupled.

**Group related widgets into subfolders.** Avoid flat widget directories with many files:
- `widgets/profile_header/` — `profile_header_section.dart`, `profile_info_section.dart`, etc.
- `widgets/membership_carousel/` — carousel, header, payment_history_section, etc.
- Standalone widgets can stay flat.

Helper functions (formatters, display builders) live in their own `_helpers.dart` file inside the subfolder.

## Screen Layout & Spacing

**Screen frame**
- Use `AppScreenScaffold` (`lib/shared/widgets/scaffold/app_screen_scaffold.dart`) for every screen. It owns the background color, top + bottom `SafeArea`, optional fixed topbar, optional fixed bottom nav, and the screen-edge horizontal inset. **Don't hand-roll `Scaffold` + `SafeArea` + `Padding` per screen** — that's exactly the duplication this widget exists to remove.
- Pass `bottomNav: AppBottomNavBar(...)` when the screen sits behind the persistent nav. Pass `topbar:` only for the rare case of a fixed topbar above the body — most screens put `AppTopbar` *inside* the scrollable, so they leave `topbar:` null.

**Horizontal padding**
- `AppScreenScaffold` defaults to `horizontalPadding: AppScreenHorizontalPadding.standard` (= `DesignConstants.screenHorizontalPadding`, 16). This is the right answer ~90% of the time.
- Use `AppScreenHorizontalPadding.big` (= `DesignConstants.paddingBig`, 32) for inset-frame screens like the photo verification flow where the design specifies a wider gutter.
- Use `AppScreenHorizontalPadding.none` when the screen renders edge-to-edge (e.g. a screen whose AppTopbar is inside the scrollable, or each section handles its own horizontal padding internally).
- **Don't apply screen-edge horizontal padding manually inside the body of a screen using `AppScreenScaffold`** — that's double-padding.

**Spacing rules**
- **NEVER use `SizedBox` for spacing.** Always use the `spacing:` parameter on `Column`/`Row`.
- **Use `DesignConstants.spacing*` constants for every spacing value.** Available: `spacingBig` (32), `spacingLarge` (16), `spacingMedium` (8), `spacingSmall` (4), `spacingTiny` (2).
- Good: `Column(spacing: DesignConstants.spacingLarge, children: [...])`
- Bad: `SizedBox(height: 16)` between Column children.
- If children need different spacing, restructure into nested Column/Row groups with uniform `spacing:` on each — do not fall back to SizedBox.
- **Exception — `ListView.separated`:** a `SizedBox` returned from its `separatorBuilder` is **fine and encouraged**. The rule targets one-off `SizedBox`es wedged between `Column`/`Row` children; `ListView.separated` has no `spacing:` parameter, so its `separatorBuilder` is the idiomatic, intended way to gap list items. Keep the height on a `DesignConstants.spacing*` constant. (Use a plain `ListView` + `Column(spacing:)` only when the list is small and you don't need lazy item-building — but `ListView.separated` is not a violation.)
- **Never use `margin`** on Container/DecoratedBox for spacing between widgets — use the parent's `spacing:` instead.
- **Never use `Padding` to create a gap between sibling widgets** — gaps belong to the parent's `spacing:` parameter, not to either of the two siblings. Padding is only for the *inside* of a single widget (screen-edge containment, internal content padding within a card, etc.). If you find yourself adding `EdgeInsets.only(top: ...)` to make space below a previous widget, stop — that's a gap, not padding. Wrap the siblings in a `Column`/`Row` with `spacing:`. For sliver layouts where you can't share a Column (e.g. between a `SliverPersistentHeader` and a `SliverList`), prefer combining adjacent `SliverToBoxAdapter`s into a single Column with `spacing:` rather than padding each one separately.
- If a repeated spacing pattern doesn't match an existing constant, extract a helper. Do not scatter magic numbers.

## Section Structure & Gap Hierarchy

A screen is usually a stack of **Sections**. Each Section is a `Column` with a Title and its Content, using `spacing: DesignConstants.spacingLarge` between them.

The Content is itself a `Column` (or similar) with `spacing: DesignConstants.spacingMedium` between its grouped pieces (subtitles, rows, cards).

Inside those pieces, the innermost groups use `spacing: DesignConstants.spacingSmall` (or `spacingTiny`) for tightly related elements — a label and its value, icon + text, chips in a row.

**Why the cascade**: gap size communicates relationship. Elements that belong together the most get the smallest gap; unrelated things get the biggest. A Title and its Content are *less* tightly related than the items *within* the Content, so the Title→Content gap must be larger than the gaps inside the Content. The same logic applies one level down: a Subtitle is less related to its sub-content than the sub-content items are to each other.

The default cascade as you descend is `spacingLarge → spacingMedium → spacingSmall`. This holds ~90% of the time; it is a default, not a strict rule — skip a level when the design actually calls for it.

**Split widgets at the Title/Content boundary** — the spot where the gap jumps to `spacingLarge` is also the natural boundary for a new widget *class*. A Section's `build` typically returns `Column(spacing: spacingLarge, children: [Text(title, ...), _Content(...)])` and nothing else, with `_Content` handling the medium-gap layer. Whether any of these become their own **files** follows the file-organization rules above.

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

Bad: one flat `Column(spacing: spacingMedium, children: [title, subtitle, row1, row2, row3])` — the title gets the same gap as unrelated rows, flattening the visual hierarchy.

Bad: `spacingSmall` between title and content and `spacingLarge` between rows — inverted cascade.

Bad: nesting the cascade but cramming it all into one giant `build` method — the cascade reveals the split points, so honor them by extracting each level into its own widget class.

## Screen Architecture

- **Screens are collections of small, focused widgets** — not monolithic build methods.
- Break screens into logical sections (`HeaderSection`, `MembersListSection`, `InfoBadgesGrid`).
- Each section has a single, clear responsibility.

**Widget naming**
- Section widgets: `[Content]Section` — `MembersSection`, `HeaderSection`.
- Item widgets: `[Item]Card`, `[Item]Tile`, `[Item]Item`, `[Item]Row` — `MemberCard`, `MemberListTile`, `BenefitRow`. `*Row` is valid for items that render as a horizontal strip inside a `*List` / `*Section` (avatar + label + meta).
- Grid/List widgets: `[Content]Grid`, `[Content]List` — `MembersGrid`, `MembersList`.
- Avoid generic names like `CustomWidget`, `WidgetOne`.

**BLoC integration in widgets**
- **Widgets dispatch events to the bloc** — never call repository methods directly.
- **Widgets listen to state changes** via `BlocBuilder` / `BlocListener` / `BlocConsumer`.
- **No callbacks for business logic** — use bloc events. Callbacks are fine for simple UI interactions (a button `onTap`, a form field `onChanged`).

**Widget separation**
- Default to extracting into its own file. If a widget has a clear name and responsibility, it gets a file.
- **Default location is shared.** A widget belongs in `lib/features/<feature>/presentation/widgets/` only if it's specifically tied to that feature's content (e.g. a class-schedule list item that knows about classes). Topbars, buttons, cards, list rows, tables, dialogs, dividers, info rows, badges, chips, sections — all live in `lib/shared/widgets/`. **When unsure, prefer shared.** Moving a feature widget to shared later is cheap; building two parallel versions because the first one was buried in a feature folder is not.
- One public widget per file.
- **Always check `lib/shared/widgets/` before building custom UI.** If a shared widget already exists for the pattern (cards, buttons, headers), use it instead of creating a parallel implementation.
- **Before building a new shared widget, also check `../CRM/lib/shared/widgets/`.** If a version of the pattern exists there (e.g. a shared data table, info rows, section cards, primary buttons), copy and adapt it rather than building from scratch. The two apps share a design language; the goal is parity, not divergence.

## Project Structure

```
lib/
├── main.dart                       # Supabase init → ThemeRuntime → AuthGate
├── core/
│   ├── app_config.dart             # tenant + boot/fallback designId (preset)
│   ├── app_routes.dart             # named-route constants + builder map
│   ├── app_slots.dart              # CombatDenSlots: expected colour/image slots
│   ├── design_constants.dart       # runtime-driven via the theme_flutter package
│   ├── config/                     # environment (Android loopback rewrite) + supabase config
│   ├── constants/                  # env_constants.dart (dotenv keys)
│   ├── errors/                     # exceptions.dart (Network / Server / Forbidden)
│   ├── network/                    # api_client.dart (JWT dio + 401 refresh + 403 guard)
│   └── state/                      # selected_member.dart (app-wide member identity)
├── features/
│   └── <feature>/
│       ├── bloc/                   # bloc + event + state (single-class state)
│       ├── data/
│       │   ├── models/             # json_serializable models (+ *.g.dart)
│       │   └── repositories/       # wrap ApiClient, throw typed exceptions
│       └── presentation/
│           ├── screens/
│           └── widgets/
└── shared/
    ├── themes/
    │   └── app_theme.dart          # ThemeData ← DesignConstants
    └── widgets/                    # cross-feature reusables
```

Outside `lib/`, **`tools/capture/`** holds dev-only Flutter capture entrypoints
that render real screens to frame-exact PNGs (1080×1920 or 1080×2340) for the
landing page: `capture_main.dart` (the theme-reel scroll), `capture_booking_main.dart`
(the class-booking clips — "Perfectly timed content"/Video-Before-Class, plus the
"you're in" booked-confirm variant via `CAPTURE_BOOKING_END=confirm`), and
`capture_app_main.dart` (the Home / Points / Streak screen clips), sharing
`capture_frame.dart`.

> ⚠️ **The capture harness is currently out of step with the live app and needs a
> separate update — do NOT assume it runs.** It was built against the old
> prototype path: it drives the dormant `selected_gym.dart` singleton
> (`selectedGym.select(...)`) and pages the **VideoService** gym browser
> (`style_select`'s `GymsPager`, `localhost:8002`) to pick a gym/theme. The live
> app replaced that with `SelectedMember` + Supabase auth + the member portal, so
> the harness can't set up a live member session. Re-pointing it (auth + member
> selection + member-portal reads, or a fixture path) is its own task. Until then
> the `make capture*` targets and their `tools/capture/README.md` describe the old
> flow — treat them as stale.

## Development Commands

- `flutter run` — run the app in debug mode (hot reload). Pass the dev dart-defines to land pre-authenticated: `--dart-define=DEV_AUTOLOGIN_EMAIL=... --dart-define=DEV_AUTOLOGIN_PASSWORD=...` (the `make run` target wires these). The live app needs the backend on `:8000` + Supabase + a seeded member.
- `flutter run --release` — release mode.
- `flutter analyze` — static analysis. **Must be clean before committing — this is the gate.**
- `flutter pub get` — install dependencies.
- Code-gen: `dart run build_runner build --delete-conflicting-outputs` after adding/changing a `json_serializable` model.
- `flutter clean` — clean build artifacts.
- `make capture` / `make capture-booking` / `make capture-app` / `make capture-shots` / `make stitch` — dev-only landing-page capture. **See the capture-harness warning above — these are stale against the live app** (they render via the dormant VideoService/`selectedGym` path and need a harness update before they work again).

## Code Quality

- **Always run `flutter analyze` after making code changes.** Fix every warning and error.
- **Zero warnings policy.** No deprecated APIs (use `.withValues()` instead of `.withOpacity()`, etc.).
- **Const constructors** wherever possible.
- Full null safety.
- No hardcoded values (see *Theming System*).

## Dependencies

- **Add dependencies with `flutter pub add <package>`.** Never edit `pubspec.yaml` by hand. Dev deps: `flutter pub add --dev <package>`.

**This list documents dependencies that carry rules or scope** — what they're for and where they may (or may not) be used.

Scoped / significant dependencies:
- `flutter_bloc` / `equatable` — state management for every live feature (Screen → Bloc → Repository). Events/states use `equatable`.
- `dio` — HTTP client behind `ApiClient` for the FastApiBackend member portal. Route every backend call through `ApiClient`, never a raw `Dio`. (`theme_flutter` also pulls a transitive `dio` for the customization engine — that one is package-internal.)
- `supabase_flutter` — **auth only** (GoTrue JWT for `ApiClient`, session refresh, `authStateChanges`). The mobile client holds no DB privileges.
- `flutter_dotenv` — loads `.env.dev` / `.env.prod` at startup for `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `API_BASE_URL` (see *Configuration*).
- `json_annotation` / `json_serializable` / `build_runner` — code-gen for API response models (`*.g.dart`).
- `mobile_scanner` — the QR check-in camera scanner (`features/qr_checkin/`). Only there.
- `shared_preferences` — persists the `SelectedMember` identity + the celebration watermark.
- `google_fonts` — Jura via `GoogleFonts.jura()` (referenced by `DesignConstants.baseFont`).
- `url_launcher` — hands a URI to the OS. Two call sites, each behind its own
  helper file (a URI builder + a launcher returning bool, so no `BuildContext`
  crosses an async gap and a failure surfaces as a `ScaffoldMessenger`
  SnackBar):
  - the class-detail Location section's "Open in Maps" deep link
    (`features/class_booking/presentation/widgets/class_location_helpers.dart`:
    `geo:0,0?q=<encoded>` on Android, `https://maps.apple.com/?q=<encoded>` on
    iOS);
  - **video playback** — there is no in-app player, so every video tap opens
    YouTube externally
    (`features/videos/presentation/widgets/video_link_helpers.dart`:
    `videoUriFor` / `launchVideoFor` / `openVideoFor`, always
    `LaunchMode.externalApplication` so the YouTube app takes it when
    installed and the browser otherwise). See *Videos open on YouTube*.

  Android 11+ package visibility means these intents silently fail unless
  `android/app/src/main/AndroidManifest.xml`'s `<queries>` block declares a
  `VIEW` intent for the `geo` and `https` schemes — that block is
  load-bearing, don't drop it.
- `url_launcher_platform_interface` + `plugin_platform_interface` — **dev
  deps only** (both already transitive; declared so tests may import them).
  They exist for `test/helpers/fake_url_launcher.dart` — see *Testing*.
- `material_symbols_icons` — `Symbols.*_sharp` icons.
- `lottie` — backs **only** the bundled booking "done" checkmark animation, which the app plays and tints to the brand primary itself (the engine no longer renders Lottie).
- `path_provider` — used **only** by the dev-only capture harness (`tools/capture/`) to write exported frames. Not part of any shipping screen.
- `theme_flutter` (path dep, `../ThemeService/ThemeFlutter`) — the shared white-label runtime extracted from this app's old `lib/customization/`. It carries the customization-engine deps (`dio`, `flutter_svg`, `cached_network_image`, `get_it`, `shared_preferences`); its `get_it` is a **transitive** locator internal to the package — **app code does NOT use `get_it`** (DI is manual constructor injection, see *State-management model*).

## Testing

- **Use `bloc_test` + `mocktail`.** Blocs hold the logic, so they get the coverage: build the bloc with a mocked repository, `act` an event, assert the emitted state sequence (loading → loaded/error). Mock repositories and `ApiClient`; never hit a live backend in a test.
- **`url_launcher` is asserted through the platform interface, not a code
  seam.** `test/helpers/fake_url_launcher.dart` (`FakeUrlLauncher`) records
  what the app asked the OS to open; install it with
  `UrlLauncherPlatform.instance = FakeUrlLauncher()` (pass `succeeds: false`
  for the "nothing handled it" path). App code stays free of test hooks.
- `flutter test` before committing.

## Configuration (dotenv + dart-defines)

- **dotenv (`.env.dev` / `.env.prod`)** — the auth/backend URLs loaded at startup via `flutter_dotenv` (keys in `lib/core/constants/env_constants.dart`; debug → `.env.dev`, release → `.env.prod`, selected in `lib/core/config/environment.dart`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`. URL-valued keys route through `EnvironmentConfig.url(...)` for the Android-emulator loopback rewrite. `.env.example` documents the shape; the env files are flutter assets and are gitignored — never commit real secrets. (A fresh worktree has none until `setup_worktree_env.sh` copies them.)
- **dart-defines** — the dev-only auto-login (`DEV_AUTOLOGIN_EMAIL` / `DEV_AUTOLOGIN_PASSWORD`, empty in prod → normal login flow), read by `LoginBloc` via `String.fromEnvironment`.

## Sibling systems in this monorepo

- `../FastApiBackend/` — the app's backend. **All** live calls go to its member portal (`/api/v1/member/...`) via `ApiClient`. Contract: the Pydantic schemas in `../FastApiBackend/src/member_portal/` (and the domain schemas it reuses).
- `../ThemeService/ThemeFlutter/` — the shared `theme_flutter` white-label runtime (path dep) that resolves branding; the gym's `theme_design_id` (from the showcase read) selects the live design.
- `../CRM/` — the gym-admin web app, which shares this app's design language. Shared widget candidates often live there too (check `../CRM/lib/shared/widgets/` before building a new shared widget).
- `../Database/` — Supabase (auth + the shared Postgres the backend reads/writes). `openapi.json` is an optional gitignored local dump.

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
