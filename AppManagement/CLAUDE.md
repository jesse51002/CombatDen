# AppManagement — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Project Status: Visual-Only Prototype

**Read this first.** This app is a **visual prototype** for demos and design iteration during the pre-build sales / MVP phase. It is the **gym admin web app** — staff/owners managing their gym from a browser.

- This is a **web-only Flutter app** (no Android, no iOS) — mirrors `../FlutterCRM/`'s platform setup.
- **Backend is off-limits with ONE carve-out.** No Supabase, no auth, no general-purpose API client. The single exception is the **read-only VideoService feed** — see *VideoService carve-out* below. Everything else stays mock-only; do not add HTTP, clients, or live data to any other screen without asking first.
- **No state management framework.** No BLoC, no providers, no Riverpod, no Redux. Use `StatelessWidget` everywhere; `StatefulWidget` only when a screen genuinely needs local UI state (e.g. tab index, scroll controller).
- **No real data.** Every list, every card, every detail screen is fed by hardcoded mock data co-located with the feature.
- **No persistence.** Buttons can be no-ops or `print` for now.

The whole point is to make screens that **look right** so the design can be evaluated, screenshotted for sales, and iterated on quickly. When this app graduates to real data, this CLAUDE.md gets revised and the data/state sections from `../FlutterCRM/CLAUDE.md` come back.

**Theme/design rules are NOT relaxed because this is a prototype.** See *Theming System* below.

## VideoService carve-out (the one live backend call)

This prototype makes exactly **one** real network call, and it is deliberate. The member-app **videos tab** pulls its feed live from the VideoService so the admin previews real thumbnails and titles instead of mock art.

- **Scope:** read-only, one endpoint — `GET /apps/{videoAppId}/videos`. No writes, no auth, no other endpoints. `videoAppId` defaults to `mma` (Apex MMA).
- **Where it lives:** `lib/features/members/data/video_api_client.dart` (`VideoApiClient`, wraps `package:http`) feeds `member_feed_section.dart`, which is the **only** place a `StatefulWidget` + `FutureBuilder` driving a network call is allowed. Models live in `lib/features/members/data/video_feed.dart` (`Video.fromJson`).
- **Dependency:** the VideoService (sibling, see below) must be running. Base URL defaults to `http://localhost:8002`; override at launch with `--dart-define=VIDEO_BASE_URL=http://<host>:<port>`.
- **Failure behavior:** the call has a 5s timeout and degrades quietly (empty feed) so the rest of the demo never breaks if the service is down.
- **`http` is whitelisted for this call only.** It is NOT the signal that the app is graduating out of prototype mode (that signal is still `flutter_bloc` / `dio` / `supabase_flutter`). Do **not** reuse `VideoApiClient` or `package:http` to wire any other screen to a backend — every other list/card/detail stays on co-located mock data per the rules above. Widening this carve-out is a decision for the user, not a default.

## Sibling repos in this monorepo

- `../FlutterCRM/` — staff/CRM web app, **fully wired** (BLoC + Supabase + Stripe). Source of truth for the design system and most shared widget patterns. When this app graduates, it follows FlutterCRM's stack.
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

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**

- **EVERY widget MUST import and use `package:app_management/core/constants/design_constants.dart`.**
- **NEVER hardcode colors** — no `Colors.red`, no inline `Color(0xFF...)`, no copy-pasted hex codes.
- **NEVER hardcode font properties** — no inline `fontFamily`, no inline `fontSize`, no inline `fontWeight`. Use the text styles in `DesignConstants` (`h1`, `h2`, `h3`, `p`, `pBig`, `pSmall`, etc.).
- **NEVER hardcode spacing, padding, radius, or border widths.** Use `DesignConstants.spacing*`, `DesignConstants.padding*`, `DesignConstants.radius*`, `DesignConstants.buttonBorderSize`.
- **Prototype status is NOT a license to inline values.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/radius/padding, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
- **`design_constants.dart` is this app's own design system and may be edited deliberately.** AppManagement has **forked** its tokens to its own identity (warm light theme, sapphire accent, Hanken Grotesk, tight 12/8 corners, de-carded layout). It is **no longer immutable** and **no longer byte-for-byte identical** with `../FlutterCRM/` or `../MobileApp/` — do **NOT** mirror token changes to them. Keep all token changes centralized in this file (so one edit reskins the whole app) and add/rename tokens only when the design genuinely needs it. See `DESIGN.md` for the system.
- **ALWAYS reference DesignConstants** for every color, every text style, every padding, every radius, every spacing.

**Icons: Use Material Symbols**

- **ALWAYS use `Symbols.*_sharp`** from `package:material_symbols_icons/symbols.dart`.
- **NEVER use `Icons.*`** from Flutter's built-in Material icons.
- **ALWAYS set `weight: DesignConstants.iconWeight`** on every `Icon()` widget.
- Good: `Icon(Symbols.person_sharp, weight: DesignConstants.iconWeight)`
- Bad: `Icon(Icons.person)`

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
- `dart format` for consistent formatting.
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
- **Before building a new shared widget, also check `../FlutterCRM/lib/shared/widgets/` AND `../MobileApp/lib/shared/widgets/`.** Both apps share a design language with this one. If a version of the pattern exists there (e.g. `app_data_table.dart`, `info_row.dart`, `section_card.dart`, `app_primary_button.dart`, `subtitle_section.dart`), copy and adapt it (rewrite imports from `package:crm/` → `package:app_management/`) rather than building from scratch. The goal is parity, not divergence.
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
└── shared/
    ├── themes/
    │   └── app_theme.dart
    └── widgets/                    # cross-feature reusables
```

## Development Commands

- `make run` — serve the web app on `http://localhost:8081` (port chosen to avoid colliding with FlutterCRM on `8080`).
- `make analyze` — static analysis. **Must be clean before committing.**
- `make format` — `dart format lib test`.
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

Current dependencies (intentionally minimal):
- `google_fonts` — for Hanken Grotesk via `GoogleFonts.hankenGrotesk()` (referenced by `DesignConstants.baseFont`).
- `material_symbols_icons` — for `Symbols.*_sharp` icons.
- `http` — **for the VideoService carve-out only** (see above). It backs `VideoApiClient` and nothing else. Adding `http` to any other client is not allowed; reach for the user first.

If you find yourself wanting to add `flutter_bloc`, `dio`, `supabase_flutter`, or anything else from the FlutterCRM stack, **stop**. That's the signal that this app is graduating out of prototype mode. Talk to the user before pulling those in. (`http` being present is **not** that signal — it is the scoped exception above, not the start of the real-data stack.)

## What changes when this becomes real

When this app moves past visual-only:

1. State management gets added — feature-by-feature BLoC, mirroring `../FlutterCRM/`.
2. `mock_*.dart` files get deleted in favor of `repositories/` + an `ApiClient` + Supabase auth.
3. Models gain `fromJson`/`toJson`, validated against `../Database/openapi.json`.
4. Money fields move to `int` minor units; date fields convert to UTC at the API boundary.
5. Tests get added (unit, widget, bloc).
6. This CLAUDE.md gets revised, importing the data/state sections from `../FlutterCRM/CLAUDE.md`.

Until that work happens, none of those concerns belong in this repo.

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
