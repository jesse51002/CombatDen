# AppManagement — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Project Status: Visual-Only Prototype

**Read this first.** This app is a **visual prototype** for demos and design iteration during the pre-build sales / MVP phase. It is the **gym admin web app** — staff/owners managing their gym from a browser.

- This is a **web-only Flutter app** (no Android, no iOS).
- **Backend is off-limits with TWO read-only carve-outs.** No Supabase, no auth, no general-purpose API client. The two deliberate exceptions are the **read-only VideoService feed** and the **read-only ThemeService theme catalog + live preview** — see *VideoService carve-out* and *ThemeService carve-out* below. Everything else stays mock-only; do not add HTTP, clients, or live data to any other screen without asking first.
- **No state management framework.** No BLoC, no providers, no Riverpod, no Redux. Use `StatelessWidget` everywhere; `StatefulWidget` only when a screen genuinely needs local UI state (e.g. tab index, scroll controller).
- **No real data.** Every list, every card, every detail screen is fed by hardcoded mock data co-located with the feature.
- **No persistence.** Buttons can be no-ops or `print` for now.

The whole point is to make screens that **look right** so the design can be evaluated, screenshotted for sales, and iterated on quickly.

**Theme/design rules are NOT relaxed because this is a prototype.** See *Theming System* below.

## VideoService carve-out (read-only live backend access)

This prototype's live backend access is **read-only and limited to the VideoService** — two endpoints, both deliberate. The member-app **videos tab** pulls its feed live so the admin previews real thumbnails and titles instead of mock art; a second read fetches the selected gym's **detail** (classes / rewards / spec) once into memory (see *Gym detail* below).

- **Scope (feed):** read-only — `GET /gyms/{gymId}/videos` (gym-id-keyed: serves that gym's feed, paginated). The feed follows the selected gym (`SelectedGym` global). No writes, no auth, no other feed endpoints. The one query knob beyond paging/genre is `?rejected=true`, which serves the scan's **rejected** list instead of the approved feed (it backs the videos tab's rejected-videos section, where the admin can keep a video back) — still read-only, still this same endpoint. This boolean is a deliberate, user-approved widening of the carve-out; do not add further parameters or endpoints without asking.
- **Gym detail (the second read):** `GET /gyms/{gymId}` via `lib/features/members/data/gym_api_client.dart` (`GymApiClient`, also `package:http`) fetches the selected gym's whole content detail (spec + classes + rewards) **once** into the `SelectedGym` global. Read-only, gym-id-keyed, same 15s-timeout-then-degrade behavior. It backs the loyalty rewards store, the videos content focus, the videos tab's **"Your videos"** row/grid (`videos_tab/your_video_tile.dart` derives each tile from `detail.classes` — class image, instructor photo, class name; falls back to bundled mock when no live classes), the phone preview, and the admin **Schedule screen** (`features/schedule/`) + the dashboard's **Upcoming Classes** card — those read the gym's classes/rewards from memory (no extra calls), so they are **gym-driven, not mock, by design**. Tapping a class card on the schedule board to **edit** carries that class's gym image + name into the Add/Edit Class form (`classFromEntry` in `mock_schedule.dart`, passed as a route argument); the form's other fields stay sample defaults and "Add New Class" stays an empty upload prompt. Don't add further endpoints or writes without asking.
- **Where it lives:** `lib/features/members/data/` — `video_api_client.dart` (`VideoApiClient`, the feed + `GET /gyms/{gymId}/videos/preview`), `gym_api_client.dart` (`GymApiClient`), and `gyms_pager.dart` (pages the gyms list for the theme/gym picker), all wrapping `package:http`; models in `video_feed.dart` / `gym_detail.dart` (`*.fromJson`). The `StatefulWidget` + `FutureBuilder` pattern that drives these reads is allowed in the widgets that consume them (`member_feed_section.dart`, `library_view.dart`).
- **Dependency:** the VideoService (sibling, see below) must be running. Base URL defaults to `http://localhost:8002`; override at launch with `--dart-define=VIDEO_BASE_URL=http://<host>:<port>`.
- **Failure behavior:** the gym browser (`/gyms`) and gym-detail (`/gyms/{id}`) calls time out after **15s** — raised from 5s because the `/gyms` list response can take ~9s to load all gym files on the small App Runner instance in production — and the video feed after 30s; all degrade quietly (empty feed / error state) so the rest of the demo never breaks if the service is down.
- **`http` is whitelisted for this call only.** Do **not** reuse `VideoApiClient` or `package:http` to wire any other screen to a backend — every other list/card/detail stays on co-located mock data per the rules above. Widening this carve-out is a decision for the user, not a default. (The ThemeService carve-out below does NOT use `http`; it goes through the `theme_flutter` package's own `dio` client.)

## ThemeService carve-out (live theme preview)

The member-app **Theme tab** (`member_app_screen.dart` → `LiveThemePreviewTab`) is a **live theme preview**: a phone frame renders branded member-app showcase screens that re-theme the instant the admin picks a theme, with the animated ones looping. This is the second deliberate live backend dependency, and it is **read-only**.

- **How it works:** the tab depends on the shared **`theme_flutter`** package (path dep, `../ThemeService/ThemeFlutter`) for the customization **runtime + resolvers** only. The **showcase widgets themselves live locally** in `lib/showcase/` (Home, Booking, Stats, Rewards, etc. — moved out of `theme_flutter`, since this app is their only consumer; they still resolve branding through `theme_flutter`'s `ThemeColor`/`ThemeImage`/`ThemeFont`/`ThemeText`/`ThemeIcon`). The tab calls `ThemeRuntime.initialize(appId: 'combatden', designId: 'ApexMMA', …ShowcaseSlots…)` once (lazily, in `LiveThemePreviewTab.initState` — idempotent), `ThemeRuntime.fetchStyles()` for the theme catalog, and `ThemeRuntime.selectDesign(id)` on tap.
- **Scope:** read-only. The engine fetches the resolved branding + the catalog (`GET /apps/{appId}/styles`) and per-style assets from the ThemeService. **No writes, no persistence** — picking a theme drives only the in-session preview; it does not save the gym's choice anywhere (that's future work needing a DB table + a FastApiBackend endpoint).
- **Where it lives:** the tab chrome is in `lib/features/members/presentation/widgets/member_app/theme_tab/` (`live_theme_preview_tab.dart`, `theme_preview_pane.dart`, `theme_grid.dart`, `theme_card.dart`) + the shared `lib/shared/widgets/phone_frame.dart`; the **showcase screens it renders are in `lib/showcase/`** (a self-contained module: the screens + `showcase_screen.dart` router, `showcase_slots.dart`, `showcase_content.dart`, `showcase_tokens.dart`, `showcase_assets.dart`, and the `celebrations/` / `home/` / `rewards/` / `support/` subfolders; bundled fallback images in `assets/showcase/`). The catalog model is the engine's `ThemeStyle` (no AppManagement-side model — we consume the engine's, DRY). The two `StatefulWidget`s here (`LiveThemePreviewTab`, `_MemberFeedSection`) are allowed by the StatefulWidget rule.
- **Dependency:** the ThemeService (top-level Python pipeline's read-only API) must be running. Base URL defaults to `http://localhost:8000`; override at launch with `--dart-define=CUST_BASE_URL=http://<host>:<port>`.
- **Failure behavior:** the engine's resolvers never throw — they fall back to bundled defaults. The catalog grid degrades quietly (an error message, no crash) if the service is down, and the phone still renders the fallback look.
- **Two design systems coexist, intentionally.** Inside the phone frame the showcase uses its own member-app-look tokens (`lib/showcase/showcase_tokens.dart` — `ShowcaseTokens`, which resolve the tenant brand live); everything around it uses AppManagement's own forked `DesignConstants`. **`ShowcaseTokens` is NOT `DesignConstants` — never merge them**; they intentionally describe two different surfaces (the previewed *member* app vs. the admin chrome). Don't try to make the preview match the admin chrome.

## Standalone theme browser (second build target)

The Theme tab doubles as a **public theme browser** that the marketing landing page links out to (prospects browse the theme library live). It ships as a **second build target of this same app** — not a separate package — so one codebase powers both surfaces and the browser is never rewritten twice.

- **The module is `LiveThemePreviewTab`** (`features/members/presentation/widgets/member_app/theme_tab/live_theme_preview_tab.dart`). The admin member-app preview embeds it; the standalone target mounts it full-screen. It is self-contained: it bootstraps `ThemeRuntime` itself and owns its selection state (`selectedGym` global + `GymsPager`). The **only** host-specific knob is its `routePath` constructor param — the URL path the previewed theme is mirrored onto as `?theme=…`. It defaults to `AppRoutes.memberAppPreview` (embedded/admin behavior, unchanged); the standalone passes `AppRoutes.home` for root-anchored deep links.
- **The standalone shell lives in `features/theme_browser/`** — `theme_browser_app.dart` (a minimal `MaterialApp` reusing `AppTheme.light`), `theme_browser_page.dart` (full-screen: top bar + the module, no `AppShell` nav rail), and `widgets/theme_browser_top_bar.dart`. Entry point: `lib/main_theme_browser.dart`.
- **The browser shares `DesignConstants` with the admin app.** Both ride the same landing-aligned design system (see *Theming System*), so the catalog grid looks identical embedded and standalone — restyle through the tokens, not per-surface. What differs is the chrome: the admin nav rail vs. the browser's **top bar** (`widgets/theme_browser_top_bar.dart`), now a Flutter port of the landing nav (CombatDen logo + wordmark · Home / Pricing links · gradient "Book a demo" CTA, reusing the shared `AppPrimaryButton`), so the browser reads as a continuation of the marketing site. Link targets are dart-defines: `LANDING_URL` (Home + wordmark, default `https://www.combatden.net`), `PRICING_URL` (default `…/pricing.html`), `BOOK_URL` (default `…/#book`).
- **URL strategy is the Flutter web default (hash).** No `usePathUrlStrategy` is configured (deliberately — adding it would change the admin app's URLs too). Deep links round-trip via the fragment (`themes.combatden.net/#/?theme=…`); `_themeFromUrl` tolerates both hash and path strategies.
- **Same backend carve-outs.** The standalone browser hits the same read-only ThemeService + VideoService (catalog + gym detail). Both must be running locally (`:8000` / `:8002`); prod uses the same two dart-defines as the admin build.
- **Build / deploy:** `make run-themes` (dev, port 8082), `make build-themes` (`--target lib/main_theme_browser.dart` + the two API dart-defines), `make deploy-themes` (S3 + CloudFront at `themes.combatden.net`). See *Production deployment* below.

## Sibling repos in this monorepo

- `../MobileApp/` — member-facing mobile prototype, same visual-only model as this app. Shared widget candidates often live here too.
- `../LandingPage/` — React marketing site. Not a Flutter sibling, but its `COPY` dict and design choices may inform copy/voice for admin screens. Read `../LandingPage/CLAUDE.md` if you're writing user-facing strings that should match marketing voice.
- `../Database/` — Supabase schemas and `openapi.json`. Irrelevant while we're prototype-only, but model field names should already match what the API will eventually return so the future swap is mechanical.
- `../VideoService/` — the read-only video feed backend this app's videos tab calls live (see *VideoService carve-out* above). Its `videos_config.yaml` is the source of truth for the feed; `Video.fromJson` must track the shape it serves. Must be running for the videos tab to populate.

## Search the web for conventions before designing

When the UX question is "how do good apps usually present X?" — login flows, empty states, error states, onboarding, pull-to-refresh, list/detail patterns, settings screens, paywalls, billing screens, permission prompts, password reset, account deletion, etc. — **search the web first.** Look at what proven web apps actually ship (Stripe Dashboard, Linear, Notion, Vercel, Intercom admin, etc.). Don't guess.

Why: convention is a usability shortcut. Users pattern-match to flows and components they've seen in other apps. Inventing a novel treatment for a normalized interaction makes the app feel wrong even if it's "creative." Worse, guessing at conventions wastes iteration cycles when the right answer is already publicly documented.

How to apply:
- For normalized patterns, run a WebSearch + WebFetch a few real apps' screenshots before proposing a layout.
- Reference platform guidelines (Material 3) when applicable.
- Quote the convention you found ("Stripe Dashboard handles empty state with X; Linear uses Y for confirmation dialogs").
- Skip the search for genuinely product-specific work (this product's unique mechanic, our brand voice, internal logic).

## General Principles

**SOLID** — single responsibility, open/closed, substitutable subtypes, segregated interfaces, depend on abstractions.
**DRY** — single source of truth for each piece of logic.
**KISS** — favor simplicity over complexity.
**YAGNI** — don't add features until needed.
**Separation of Concerns** — separate UI from any logic that creeps in.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills are living documents

When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new live backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, a feature that changed the architecture), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**

- **EVERY widget MUST import and use `package:app_management/core/constants/design_constants.dart`.**
- **NEVER hardcode colors** — no `Colors.red`, no inline `Color(0xFF...)`, no copy-pasted hex codes.
- **NEVER hardcode font properties** — no inline `fontFamily`, no inline `fontSize`, no inline `fontWeight`. Use the text styles in `DesignConstants` (`h1`, `h2`, `h3`, `p`, `pBig`, `pSmall`, etc.).
- **NEVER hardcode spacing, padding, radius, or border widths.** Use `DesignConstants.spacing*`, `DesignConstants.padding*`, `DesignConstants.radius*`, `DesignConstants.buttonBorderSize`.
- **Prototype status is NOT a license to inline values.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/radius/padding, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
- **`design_constants.dart` is this app's own design system and may be edited deliberately.** AppManagement's tokens are **landing-aligned** — they match the marketing landing page's design system (`../LandingPage/hifi/ds.jsx`) so the public theme browser reads as an extension of it: cool off-white ground (`#F3F5F8`), white lifted cards with soft layered shadows (`cardShadow` / `buttonShadow`), the sapphire accent + its `primaryGradient`, Geist (`baseFont` / `monoFont`), tight 12/8 corners with 20px object cards. It is **no longer immutable** and **no longer byte-for-byte identical** with `../MobileApp/` — do **NOT** mirror token changes to it. Keep all token changes centralized in this file (so one edit reskins the whole app) and add/rename tokens only when the design genuinely needs it. See `DESIGN.md` for the system.
- **ALWAYS reference DesignConstants** for every color, every text style, every padding, every radius, every spacing.

**Icons: Prefer Material Symbols, Material `Icons.*` allowed**

- **Default to `Symbols.*_sharp`** from `package:material_symbols_icons/symbols.dart` — they're the design system's primary glyph set and carry the variable `weight` axis the look depends on. (That variable `weight` axis is exactly why prod builds must pass `--no-tree-shake-icons` — see *Production deployment*.)
- **`Icons.*` from Flutter's built-in Material icons is permitted.** The design system is its own fork now and isn't locked to a single icon family; `Icons.*` values are plain `IconData` and are fine to use directly — including stored on plain mock-data models. There's no need to round-trip them back to `Symbols.*` at render time.
- **Set `weight: DesignConstants.iconWeight` on `Symbols.*_sharp` icons** (it drives their stroke weight). Plain `Icons.*` glyphs don't honor the weight axis, so it's a no-op there — don't bother.
- **NEVER hardcode `size:` on any `Icon()`** (either family). Use `DesignConstants.iconSize*` — `iconSizeBig` (32), `iconSizeLarge` (24), `iconSizeMedium` (20, the default), `iconSizeSmall` (18), `iconSizeTiny` (16). Same Big→Tiny cadence as `spacing*`. If a size doesn't match one, snap to the nearest token or ask before adding a new one.
- Good: `Icon(Symbols.person_sharp, size: DesignConstants.iconSizeMedium, weight: DesignConstants.iconWeight)`
- Also fine: `Icon(Icons.person, size: DesignConstants.iconSizeMedium)`

**App Theme**

- Global `ThemeData` lives in `lib/shared/themes/app_theme.dart` and is wired in `main.dart`. It maps DesignConstants into Material 3's `ColorScheme` and `TextTheme` so stock Material widgets (`ElevatedButton`, `Text`, `Scaffold`, etc.) auto-theme.
- For widget-specific styling beyond what the global theme provides, reach into `DesignConstants` directly. Don't add one-off overrides at the call site.

## Hardcoded Mock Data Conventions

- **Mock data is co-located with its feature**: `lib/features/<feature>/data/mock_<thing>.dart`.
- Use top-level `const` lists or simple factory functions returning realistic, varied data. Don't make every member named "John Doe" — give the demo screens enough texture to actually evaluate the design.
- **Models are plain Dart classes.** No `fromJson`/`toJson` yet. Field names and types must match what the real API will eventually return (see `../Database/openapi.json` when it's relevant) so the swap to real repositories is mechanical.
- **No callbacks for "save" / "submit" actions.** Buttons can be no-ops or `print` for now. Don't pretend the prototype has logic.
- **No real loading/error/empty states wired to conditions that can't fire yet.** If a screen needs to demo those states, drive them from a hardcoded enum at the top of the screen file so they're easy to flip during a demo:
  ```dart
  enum _DemoState { loaded, empty, error }
  const _state = _DemoState.loaded;
  ```

## Dart Standards

**Imports**
- **ALWAYS use package imports** (`package:app_management/...`) — never relative imports.
- Good: `import 'package:app_management/features/members/data/mock_members.dart';`
- Bad: `import '../data/mock_members.dart';`

**Naming**
- Files: `member_card.dart`, `mock_members.dart`
- Classes: `MemberCard`, `MembersScreen`
- Functions/variables: `buildMemberCard`, `memberCount`
- Constants: `kMaxItems`
- Private: `_internalVar`, `_PrivateWidget`

**Formatting**
- Max 80 characters per line.
- **Hand-format. Do NOT run `dart format` / `make format` in this app.** The repo isn't format-clean, so a blanket format rewrites ~60 files — including the deliberately-forked `design_constants.dart` — and buries your actual change in churn. Match the surrounding style by hand instead.
- **`flutter analyze` (`make analyze`) is the gate, not formatting.** Keep it clean before committing.
- Trailing commas on multi-line widget trees for clean diffs.

**Type Hints**
- Always annotate function parameters and return values.
- Use `?` for nullable types. Use generics (`List<Member>`, `Map<String, int>`).

**Resilient Enum Parsing**
- Even though data is hardcoded today, build the muscle memory: any enum that *will* be parsed from JSON later must have a fallback in its `fromJson` (when added) using `firstWhere(..., orElse: ...)`. For now, just include an `unknown` (or equivalent default) variant on status-like enums so it's already there when real data arrives.

**Backend String Display**
- Capitalize lowercase strings (`'recurring'`, `'active'`) before displaying. Even with hardcoded data, display them the way the real API will hand them to us, so the formatter call site is already in place.

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

**Horizontal padding**
- Use `DesignConstants.screenHorizontalPadding` for all screen-level horizontal padding. Visual consistency across screens is non-negotiable.

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
- Item widgets: `[Item]Card`, `[Item]Tile`, `[Item]Item` — `MemberCard`, `MemberListTile`.
- Grid/List widgets: `[Content]Grid`, `[Content]List` — `MembersGrid`, `MembersList`.
- Avoid generic names like `CustomWidget`, `WidgetOne`.

**Widget separation**
- Default to extracting into its own file. If a widget has a clear name and responsibility, it gets a file.
- **Default location is shared.** A widget belongs in `lib/features/<feature>/presentation/widgets/` only if it's specifically tied to that feature's content. Topbars, buttons, cards, list rows, tables, dialogs, dividers, info rows, badges, chips, sections — all live in `lib/shared/widgets/`. **When unsure, prefer shared.** Moving a feature widget to shared later is cheap; building two parallel versions because the first one was buried in a feature folder is not.
- One public widget per file.
- **MANDATORY: check `lib/shared/widgets/` before writing a single line of new widget code.** This is not a soft suggestion — it is the first step on every UI task. Run `ls lib/shared/widgets/` (and `ls lib/shared/widgets/*/` for subfolders) BEFORE you start composing widgets. If a shared widget already covers the pattern (cards, buttons, headers, tables, list rows, info rows, dialogs, search boxes, filter bars, view switchers, etc.), USE IT. Do not build a parallel implementation, do not "simplify" it inline, do not write a one-off version because yours is "just a little different." Pass parameters or extend the shared widget. The whole point of having a shared widget library is that every screen looks identical because every screen uses the same primitives. Two parallel implementations is the bug we are designing this rule to prevent.
- **Tables specifically:** if you are about to write any kind of table (header row + data rows + dividers + sticky-or-not + tappable-or-not), the answer is `AppDataTable` from `lib/shared/widgets/app_data_table.dart`. Do not handroll headers, rows, or dividers. Configure `AppDataTableColumn` and `AppDataTableRow` instead.
- **Before building a new shared widget, also check `../MobileApp/lib/shared/widgets/`.** The member app shares a design language with this one. If a version of the pattern exists there (e.g. a shared data table, info rows, section cards, primary buttons), copy and adapt it (rewrite imports from `package:mobile_app/` → `package:app_management/`) rather than building from scratch. The goal is parity, not divergence.
- **If you skip this check, you will be asked to redo the work.** This has already happened once — a contributor built a custom table for a list-of-rows pattern when `AppDataTable` was sitting in shared, and the work had to be torn out and rewritten.

## Project Structure

```
lib/
├── main.dart
├── core/
│   └── constants/
│       └── design_constants.dart   # this app's forked design system
├── features/
│   └── <feature>/
│       ├── data/
│       │   └── mock_<thing>.dart   # hardcoded prototype data
│       └── presentation/
│           ├── screens/
│           └── widgets/
├── shared/
│   ├── themes/
│   │   └── app_theme.dart
│   └── widgets/                    # cross-feature reusables
└── showcase/                       # member-app preview screens rendered in the
                                    # theme tab (moved from theme_flutter); see
                                    # the ThemeService carve-out above
```

## Development Commands

- `make run` — serve the admin web app on `http://localhost:8081`.
- `make run-themes` — serve the **standalone theme browser** on
  `http://localhost:8082` (second build target — see *Standalone theme browser*
  below). Runs alongside `make run` on its own port.
- `make analyze` — static analysis. **Must be clean before committing — this is the gate.**
- `make format` — `dart format lib test`. **Avoid in this app** (see *Formatting* above): the repo isn't format-clean, so it churns ~60 files including the forked `design_constants.dart`. Hand-format instead.
- `make test` — run all tests.
- `make get` — `flutter pub get`.
- `make clean` / `make reset` — clean build artifacts / clean + get.
- `make doctor` — `flutter doctor`.

Direct equivalents if you don't want the Makefile:
- `flutter run -d web-server --web-port 8081`
- `flutter analyze`
- `flutter test`
- `flutter pub get`

## Code Quality

- **Always run `flutter analyze` after making code changes.** Fix every warning and error.
- **Zero warnings policy.** No deprecated APIs (use `.withValues()` instead of `.withOpacity()`, etc.).
- **Const constructors** wherever possible.
- Full null safety.
- No hardcoded values (see *Theming System*).

## Dependencies

- **Add dependencies with `flutter pub add <package>`.** Never edit `pubspec.yaml` by hand.
- Dev dependencies: `flutter pub add --dev <package>`.

**This list is not an exhaustive inventory of `pubspec.yaml`.** It documents only the dependencies that carry **rules or scope** — what they're for and where they may (or may not) be used. A routine, self-explanatory UI utility (e.g. a scroll-position helper like `scrollable_positioned_list`) does **not** need a line here; only document a dependency when its use is **scoped, restricted, or architecturally significant** (a carve-out, the design-system font, or the no-go list below). Adding a minor utility is not a "real divergence" that the living-document rule requires you to record.

Scoped / significant dependencies (intentionally minimal):
- `google_fonts` — for Geist (the landing page's typeface) via `GoogleFonts.geist()` / `GoogleFonts.geistMono()` (referenced by `DesignConstants.baseFont` / `monoFont`).
- `material_symbols_icons` — for `Symbols.*_sharp` icons.
- `flutter_markdown_plus` — renders the agent view's read-only prompt panel (the feed's `videos_desc` / `avoid_desc`, which the VideoService stores as markdown). A maintained fork of the discontinued `flutter_markdown`; styling is driven from `DesignConstants`. Used only there.
- `http` — **for the VideoService carve-out only** (see above). It backs `VideoApiClient` and nothing else. Adding `http` to any other client is not allowed; reach for the user first.
- `theme_flutter` (path dep, `../ThemeService/ThemeFlutter`) — **for the live theme preview carve-out only** (see *ThemeService carve-out* above). It is the shared white-label runtime + resolvers (the showcase screens now live locally in `lib/showcase/`). It transitively pulls in `dio`, `flutter_svg`, and `get_it`. **This is a named, user-approved exception scoped to the theme preview feature** — those transitive packages are NOT a license to wire `dio` into other screens or to start the real-data stack. Do not import them directly elsewhere.
- `cached_network_image` — **for the relocated `lib/showcase/` only** (it backs `ShowcaseAsset.network`, which loads the gym's reward / class photos in the preview). It came in as a direct dep when the showcase moved here from `theme_flutter`. Scoped to the showcase; don't reach for it in other screens (the schedule board / class form use plain `Image.network`).
- `url_launcher` — used **only** by the standalone theme browser's top bar (`features/theme_browser/.../theme_browser_top_bar.dart`) to open the header's Home / Pricing / Book-a-demo links (`LANDING_URL` / `PRICING_URL` / `BOOK_URL`). Routine UI utility; not part of the real-data stack.

If you find yourself wanting to add `flutter_bloc`, `supabase_flutter`, or anything else from the real-data stack — or to use the transitive `dio` for a new client — **stop**. That's the signal that this app is leaving prototype mode. Talk to the user before pulling those in. (`http` and the `theme_flutter` dependency being present are **not** that signal — they are the scoped exceptions above, not the start of the real-data stack.)

## Production deployment (web)

The app deploys as a static build to **S3 + CloudFront** at
`https://app.combatden.net` (mirrors `../LandingPage/deploy/`). See
`../DEPLOYMENT.md` for the full runbook.

`web/` is CombatDen-branded (not the Flutter template): the tab `<title>`,
`manifest.json`, and the favicon + PWA icons (generated from the logo in
`assets/images/combatden_logo.png`) all carry the brand. `web/` is shared by
both build targets, so the admin app and the theme browser get the same
favicon/title in the browser.

- **Build for prod with the two API URLs** — they override the `localhost`
  carve-out defaults documented above:
  `make build-web` → `flutter build web --release --base-href=/ --no-tree-shake-icons --dart-define=CUST_BASE_URL=https://theme.combatden.net --dart-define=VIDEO_BASE_URL=https://video.combatden.net`,
  followed by `python3 deploy/prune_web_fonts.py build/web`.
- **`--no-tree-shake-icons` is required, and the font prune that follows it is
  not optional.** Icon tree-shaking only runs in release builds (never in
  `flutter run`), and it corrupts the variable `weight` axis of the
  `MaterialSymbolsSharp` font — so every `Symbols.*_sharp` icon (the whole nav
  bar, etc.) renders in debug but **disappears on deploy** (flutter/flutter#183381).
  The flag fixes that by shipping the full font with its axes intact. But it also
  ships the package's two **unused** families full (Rounded ~15 MB + Outlined
  ~10 MB), and Flutter web loads every `FontManifest.json` font eagerly at
  startup, so `deploy/prune_web_fonts.py` deletes those two `.ttf`s from
  `build/web` and strips them from the manifest post-build (~25 MB saved; the app
  uses only Sharp). Both `make build-web` and `make build-themes` run the flag +
  prune. **Don't remove either piece without restoring the other** — the flag
  alone bloats the bundle; the prune alone (without the flag) re-breaks icons.
- **Deploy tooling lives in `deploy/`** (boto3, its own `pyproject.toml`):
  `make deploy-provision` (S3 bucket + ACM cert), `make deploy-finalize`
  (CloudFront — includes a 403/404 → `/index.html` SPA fallback so deep links
  and refresh resolve), then `make deploy` (build + upload + invalidate). DNS
  records are added by hand at Squarespace.
- Both backends are served over HTTPS at their own subdomains
  (`theme.`/`video.combatden.net`), so there is **no mixed-content issue** and
  the APIs' open CORS (`["*"]`) covers the cross-origin calls. **No Dart code
  changes are needed for prod** — only the two dart-defines at build time.

**Second deployment — the standalone theme browser** (see *Standalone theme
browser* above) ships from the **same project, a different `--target`**, to its
own subdomain `https://themes.combatden.net`.

- **Build:** `make build-themes` →
  `flutter build web --release --base-href=/ --target lib/main_theme_browser.dart`
  plus the same two API dart-defines as the admin build.
- **Deploy tooling lives in `deploy-themes/`** — a copy of `deploy/` whose
  `config.py` points at bucket `combatden-themes` / domain
  `themes.combatden.net`. The boto3 scripts are config-driven and otherwise
  identical: `make deploy-themes-provision` / `-finalize` / `deploy-themes`.
- Both targets emit to `build/web`, so the admin and themes deploys are
  **sequential, never simultaneous** (build admin → `deploy`; build themes →
  `deploy-themes`). Fine for manual deploys.

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
