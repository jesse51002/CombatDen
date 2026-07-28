# MobileApp — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Project Status: Visual-Only Prototype

**Read this first.** This app is a **visual prototype** for demos and design iteration during the pre-build sales / MVP phase.

- **Mostly no backend.** No Supabase, no auth. The live exceptions all do real **read-only** HTTP via `dio` + disk-cached `cached_network_image`: (a) the **customization engine** (the shared `theme_flutter` package, `../ThemeService/ThemeFlutter`, fetches the tenant's branding), and (b) the **VideoService-backed content** (`../VideoService/`) — the **videos feature** (`lib/features/videos/`, the feed), the **gym detail** read that supplies classes + rewards (`lib/features/gym/`; classes consumed by `lib/features/class_booking/` + the home schedule; rewards consumed by the rewards feature's Points Store / My Rewards `lib/features/rewards/` and the post-class stats **Rewards card** `lib/features/stats/`, which renders the live rewards with a bundled-asset fallback), and the **gym-browser / style picker** (`lib/features/style_select/`). All of these read the active gym **by id** — see *Videos feature is live* below. Don't add HTTP anywhere else without asking.
- **No state management framework.** No BLoC, no providers, no Riverpod, no Redux. Use `StatelessWidget` everywhere; `StatefulWidget` only when a screen genuinely needs local UI state (e.g. tab index, scroll controller). The live features fetch via `FutureBuilder` + a cached repository, not a state framework.
- **No real data, except the live features above.** Every other list, card, and detail screen is fed by hardcoded mock data co-located with the feature.
- **No persistence.** Buttons can be no-ops or `print` for now.

The whole point is to make screens that **look right** so the design can be evaluated, screenshotted for sales, and iterated on quickly.

**Theme/design rules are NOT relaxed because this is a prototype.** See *Theming System* below.

## Videos feature is live

The videos feature (`lib/features/videos/`) is **real**, not mock. It reads the
active tenant's feed from the **VideoService** (`../VideoService/`, a read-only
HTTP API). Architecture, mirroring the customization engine:

- **`core/video_service_config.dart`** — `kVideoBaseUrl`, the VideoService base
  URL (defaults to `localhost:8002`, overridable with
  `--dart-define=VIDEO_BASE_URL`), shared by the video + class-card features.
  Content is fetched **by gym id**: the app reads the gym's whole detail once
  (`GET /gyms/{gymId}` → spec + classes + rewards, held in memory) and the
  paginated feed from `GET /gyms/{gymId}/videos` (+ `/videos/preview`). The gym
  is the active selection (`selectedGym.gymId`); a theme is **branding-only**,
  and the old theme-keyed content endpoints
  (`/apps/{appId}/themes/{designId}/...`) were **removed**. There is no app-side
  theme→feed table.
- **`data/video.dart`** — the `Video` model (matches the API's `VideoCard`). The
  fine-grained `tags` and the server-derived coarse `bigGroups` both come down on
  each video as plain `List<String>`, taken verbatim from the API. The app owns
  **no** tag/group enum or vocabulary — the server owns it, the client just
  renders whatever strings arrive (auto-formatted via `displayLabel`). This is
  deliberate: there is no closed enum to keep in sync with VideoService.
- **`data/video_api_client.dart`** — `dio` client, gym-id-keyed
  (`selectedGym.gymId`). Two reads: `fetchPreview()` →
  `GET /gyms/{gymId}/videos/preview` (the home feed in ONE request — each genre
  sampled individually, top 10, server-side, so no carousel is starved by
  pagination), and `fetchTag(tag)` → `GET /gyms/{gymId}/videos?video_type=…`
  (one genre's full list for a carousel's "view all"). 30s timeouts.
- **`data/video_feed_repository.dart`** — `VideoFeedRepository.instance`, a lazy
  app-wide singleton. `feed()` is the per-genre **home preview** cached per gym;
  `tagFeed(tag)` is one genre's full list cached per (gym, tag). Switching gym
  switches the feed with it. (No `get_it`; the customization locator is
  package-internal.)
- **`data/video_selectors.dart`** — pure derivations: top-filter scoping via
  `bigGroups`, one carousel per `tag`, featured = most-viewed, and the picks for
  the recommendation surfaces. There is no client-side tag→big-group map: the
  coarse grouping comes straight from each video's server-sent `big_groups`.

Top filters are derived from the distinct `big_groups` present in the loaded
feed (an `All` tab plus one per group, labels auto-formatted), and filter the
home feed **in place**; sub-groups are per-`tag` sections. Tapping a video is a
`debugPrint` no-op (real YouTube playback needs `url_launcher`, a deliberate
follow-up). Mock video data and the old detail screen were deleted.

**How that feed is arranged is the tenant's `videos_format`** (see *Layout and
motion formats* below). `VideosScreen` derives one `VideosLayoutData` payload —
tabs, hero, sections, callbacks — and `widgets/videos_feed_body.dart` switches
on `ThemeLayout.videos()` to one of the five layouts in
`presentation/layouts/`, each of which arranges that identical payload and
**must** render every element in it. The screen's scroll is a `CustomScrollView`
and each layout returns a sliver, so a format can pin its filter (`mosaic`) or
its rail (`tagRail`). `test/videos_invariants_test.dart` is the gate that proves
no layout adds or drops an element.

**The home schedule is a live/mock hybrid.**
`lib/features/home/data/schedule_generator.dart` builds the day's classes from
the selected gym's **live** classes (from the `GET /gyms/{gymId}` detail), then
drapes demo-only texture over them: real calendar day labels via `DateTime.now()`,
fixed time slots the classes rotate through, and seeded attending/booked flags.
This is intentional — generated demo texture computed on top of live feed data
(seeded `Random`, real dates) is **not** a "no real data" violation. "Every
other screen is hardcoded mock" applies to the screens that are *not* on a live
carve-out.

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
**Separation of Concerns** — separate UI from any logic that creeps in.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new live backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, a feature that changed the architecture), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Always delete dead code

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
- **Prototype status is NOT a license to inline values.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/padding/radius/border/divider/icon-size, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
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

- Global `ThemeData` lives in `lib/shared/themes/app_theme.dart` and is wired in `main.dart`. It maps DesignConstants into Material 3's `ColorScheme` and `TextTheme` so stock Material widgets (`ElevatedButton`, `Text`, `Scaffold`, etc.) auto-theme.
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
do not bake in assumptions that only colour and text vary.

- **Which preset is active is declared in `lib/core/app_config.dart`** —
  `AppConfig.appId` (tenant, e.g. `combatden`) and `AppConfig.designId` (the
  preset/run, e.g. `20260518T131056Z`). This is the app's identity, not part
  of the customization package. **Read this file first** to learn what is
  actually loaded.
- **The preset lives in `../ThemeService/apps/<appId>/<designId>/`.**
  Before diagnosing or changing anything about how the app looks, read:
  - `customization.yaml` — the design brief: `design_direction` (name +
    intent, e.g. "Duck Groove") and `colors_direction`, whose
    **`colors_direction.mode`** (`light`/`dark`) says whether the preset is
    *intentionally* light or dark.
  - `output.yaml` — the resolved output the app consumes: the four colour
    slots (`primary`, `background`, `text`, `accent`), plus every generated
    image and its prompt.
  - `final_images/` — the resolved bitmap assets (logo, belt, sparkles).
- **Never assume the dark CombatDen palette.** Always resolve the active
  preset via `app_config.dart`, then read that preset's `customization.yaml`
  + `output.yaml`. A light preset (`color_set.mode: light`) is a deliberate,
  supported configuration, not a bug.
- The app maps only those four slots through `BrandColor` / `CombatDenSlots`.
  Elevated surfaces (`card`, `popup`) are a translucent **white** overlay
  whose alpha tracks the background's HSL lightness, so they self-adjust to
  any preset and stack for layered surfaces. `divider` is keyed to `text`
  (a separating line needs contrast against the surface, not elevation).
  Material's discrete light/dark `ColorScheme` is driven by
  `DesignConstants.isLightCanvas`, which resolves from the loaded
  customization's `color_set.mode` (defaulting to dark when none is loaded).

## Hardcoded Mock Data Conventions

- **Mock data is co-located with its feature**: `lib/features/<feature>/data/mock_<thing>.dart`.
- Use top-level `const` lists or simple factory functions returning realistic, varied data. Don't make every member named "John Doe" — give the demo screens enough texture to actually evaluate the design.
- **Models are plain Dart classes.** No `fromJson`/`toJson` yet. Field names and types must match what the real API will eventually return (see Pydantic schemas in `../FastApiBackend/src/<domain>/<domain>_schema.py` when relevant) so the swap to real repositories is mechanical.
- **No callbacks for "save" / "submit" actions.** Buttons can be no-ops or `print` for now. Don't pretend the prototype has logic.
- **No real loading/error/empty states wired to conditions that can't fire yet.** If a screen needs to demo those states, drive them from a hardcoded enum at the top of the screen file so they're easy to flip during a demo:
  ```dart
  enum _DemoState { loaded, empty, error }
  const _state = _DemoState.loaded;
  ```

## Dart Standards

**Imports**
- **ALWAYS use package imports** (`package:mobile_app/...`) — never relative imports.
- Good: `import 'package:mobile_app/features/members/data/mock_members.dart';`
- Bad: `import '../data/mock_members.dart';`

**Naming**
- Files: `member_card.dart`, `mock_members.dart`
- Classes: `MemberCard`, `MembersScreen`
- Functions/variables: `buildMemberCard`, `memberCount`
- Constants: `kMaxItems`
- Private: `_internalVar`, `_PrivateWidget`

**Formatting**
- Max 80 characters per line **for body code**. Package imports are exempt — Dart's formatter doesn't break import lines, and renaming folders to fit a column limit isn't worth it.
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

**Widget separation**
- Default to extracting into its own file. If a widget has a clear name and responsibility, it gets a file.
- **Default location is shared.** A widget belongs in `lib/features/<feature>/presentation/widgets/` only if it's specifically tied to that feature's content (e.g. a class-schedule list item that knows about classes). Topbars, buttons, cards, list rows, tables, dialogs, dividers, info rows, badges, chips, sections — all live in `lib/shared/widgets/`. **When unsure, prefer shared.** Moving a feature widget to shared later is cheap; building two parallel versions because the first one was buried in a feature folder is not.
- One public widget per file.
- **Always check `lib/shared/widgets/` before building custom UI.** If a shared widget already exists for the pattern (cards, buttons, headers), use it instead of creating a parallel implementation.
- **Before building a new shared widget, also check `../CRM/lib/shared/widgets/`.** If a version of the pattern exists there (e.g. a shared data table, info rows, section cards, primary buttons), copy and adapt it rather than building from scratch. The two apps share a design language; the goal is parity, not divergence.

## Project Structure

```
lib/
├── main.dart
├── core/
│   ├── app_config.dart             # active tenant + designId (preset)
│   ├── app_routes.dart             # named-route constants + builder map
│   ├── app_slots.dart              # CombatDenSlots: expected colour/image slots
│   └── design_constants.dart       # runtime-driven via the theme_flutter package
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

Outside `lib/`, **`tools/capture/`** holds dev-only Flutter capture entrypoints
that render real screens to frame-exact PNGs (1080×1920 or 1080×2340) for the
landing page: `capture_main.dart` (the theme-reel scroll), `capture_booking_main.dart`
(the class-booking clips — "Perfectly timed content"/Video-Before-Class, plus the
"you're in" booked-confirm variant via `CAPTURE_BOOKING_END=confirm`), and
`capture_app_main.dart` (the Home / Points / Streak screen clips), sharing
`capture_frame.dart`. NOT shipping code — its only app-side hooks are opt-in and
inert in normal use (all null / false / clock-unset): `captureController` on
`VideosScreen`; `classData` on `ClassScreen`; `captureContentOnly` on
`ClassBookedScreen`; and the global `captureRevealClock`
(`lib/shared/widgets/animation/capture_reveal_clock.dart`) that drives the
reveal + post-class celebration animations deterministically — read by
`ScaleReveal`, `StaggeredReveal`, `CountUpText`, `LoadingDots`, the points/streak
intro controllers (`_PointSphere`/`_StreakOrbit`), and the streak badge pulse.
See `tools/capture/README.md`.

Also outside `lib/`, **`docs/`** holds design proposals for this app. Today that
is `layout_and_motion_formats.md` — the layout and motion enum library (one
whole-screen layout enum per major screen, plus a motion personality and five
per-surface motion slots), with `layout_formats_preview.html` rendering every
value as a wireframe specimen.

That doc is **design intent, not the contract** — the code is. Where they
disagree, fix the doc. `lib/core/app_slots.dart` declares the layout and motion
slots; `lib/core/formats/` holds the enums, the `ThemeLayout` resolver, the
`--dart-define` overrides and the in-app dev picker. Two screen enums are wired
so far: `app_shell_format` (`lib/shared/widgets/topbar/layouts/` + the bottom
nav) and `videos_format` (`lib/features/videos/presentation/layouts/`). Every
wired enum owns two tests — an invariant gate (`test/*_invariants_test.dart`,
always run) proving each value renders the identical element set, and a golden
preview (`test/*_preview_test.dart`, tagged `golden`). When another enum is
wired, add both and update this list and that doc in the same change.

## Development Commands

- `flutter run` — run the app in debug mode (hot reload).
- `flutter run --release` — release mode.
- `flutter analyze` — static analysis. **Must be clean before committing.**
- `flutter pub get` — install dependencies.
- `flutter pub upgrade` — upgrade dependencies.
- `flutter clean` — clean build artifacts.
- `make capture` / `make capture-booking` / `make capture-app` / `make
  capture-shots` / `make stitch` — dev-only landing-page capture: render real
  screens to frame-exact webm (or PNG screenshots). `capture` = the video-feed
  theme reel (one per theme); `capture-booking` = the class-booking clips (class
  detail → ~1s dots → "Video Before Class", one per discipline; or the "you're
  in" confirm variant); `capture-app` = the Home / Points / Streak screen clips,
  each branded to barre / muaythai / reformer; `capture-shots` = static
  screenshots for any discipline (PNGs to `LandingPage/media-src/screenshots/`) of
  the Home / Rewards / Videos screens plus the `wins` (Today's wins stats-final),
  `booked` ("Class Booked" confirmation) and `prevideo` ("Video Before Class")
  screens. Needs a running emulator + both backends
  (`make api` in `../ThemeService` and `../VideoService`). See
  `tools/capture/README.md`.

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
- `google_fonts` — for Jura via `GoogleFonts.jura()` (referenced by `DesignConstants.baseFont`).
- `material_symbols_icons` — for `Symbols.*_sharp` icons.
- `path_provider` — used **only** by the dev-only capture harness
  (`tools/capture/`) to write exported frames to the device's external files
  dir. Not used by any shipping screen; it's a benign platform util, not part of
  the real-data stack.
- `theme_flutter` (path dep, `../ThemeService/ThemeFlutter`) — the shared white-label runtime extracted from this app's old `lib/customization/`. It carries the live-feature deps (`dio`, `flutter_svg`, `cached_network_image`, `get_it`, `shared_preferences`) that back the customization engine; those are the documented live exceptions, not the start of the real-data stack. (`lottie` is a direct MobileApp dep — it backs only the bundled booking "done" checkmark animation, which the app plays and tints to the brand primary itself; the engine no longer renders Lottie.)

If you find yourself wanting to add `flutter_bloc`, `dio`, `supabase_flutter`, or anything else from the real-data stack, **stop**. That's the signal that this app is leaving prototype mode. Talk to the user before pulling those in.

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
