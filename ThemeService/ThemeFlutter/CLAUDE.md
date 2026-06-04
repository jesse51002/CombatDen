# ThemeFlutter — Coding Standards

This file guides Claude Code when working in this package.

## What this is

`theme_flutter` is a **shared Flutter package** (not an app). It is the
white-label customization **runtime**: it fetches a tenant's resolved branding
from the ThemeService API at startup, disk-caches the last-good copy,
and exposes brand-overridable resolvers (`ThemeColor`, `ThemeImage`,
`ThemeIcon`, `ThemeFont`, `ThemeText`). It is **runtime + resolvers only** — it
ships no screens and no bundled assets of its own.

The **showcase** preview screens (Home/Booking/Stats/Rewards/etc.) used to live
here (`lib/showcase/`) but were **moved into `../CRM`**
(`CRM/lib/showcase/`), since the admin app's live theme preview is
their only consumer. They still depend on this package's resolvers/runtime —
that's the allowed direction (an app importing the shared package), and it keeps
this package app-agnostic (see *Hard rules*).

It was extracted from `../MobileApp/lib/customization/` so two systems can share
it:
- **`../MobileApp`** — the member app; its real screens consume the resolvers,
  and `lib/core/design_constants.dart` is driven by them.
- **`../CRM`** — the admin app; its live theme preview owns the
  showcase screens (`lib/showcase/`) and switches themes via `selectDesign`,
  resolving branding through this package's runtime.

**NOT to be confused with `../ThemeService`** — that is the Python
pipeline that *generates* the configs this package *consumes*. Different system,
different language; the name collision is why this package is
`theme_flutter`.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever this package genuinely diverges from what this CLAUDE.md says (a removed/added resolver, a changed `ThemeRuntime.initialize` signature, a moved file, a rule the code has outgrown on purpose), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Hard rules

- **App-agnostic by construction.** This package must NEVER import from
  `package:mobile_app/...`, `package:crm/...`, or any app. The only
  app-specific inputs are injected through `ThemeRuntime.initialize`
  (`appId`, `designId`, the six `expected*` slot lists). If you need an app
  constant, add it to `EngineTokens` (engine-internal defaults) or take it as a
  parameter — never reach into a consuming app.
  - Enforce: `grep -rn 'package:mobile_app\|package:crm' lib` must be
    empty.
- **Brand values resolve LIVE.** Colours/fonts/images/text/icons come
  from the loaded customization via the resolvers; the only hardcoded values are
  the const CombatDen fallbacks (in `EngineTokens`) used when nothing is loaded.
  Resolvers never throw. (`ShowcaseTokens`, the showcase's member-app-look
  fallbacks, moved to CRM with the showcase.)
- **Web-safe.** Both consumers build for Flutter web (CRM is web).
  No `dart:io`, no `File`, no `Platform.*`. Verify with a consumer's
  `flutter build web`.
- **No bundled assets.** This package ships no `assets/` of its own — the
  showcase's bundled fallback images moved to CRM
  (`CRM/assets/showcase/`) with the showcase code. Brand images
  resolve live via `ThemeImage`; the consuming app owns any bundled fallbacks.

## Style

Follows the same conventions as `../MobileApp/CLAUDE.md`: `Symbols.*_sharp`
icons with `weight`/`size`, `spacing:` on Column/Row (never `SizedBox` for
gaps between Column/Row children — but a `SizedBox` in a
`ListView.separated` `separatorBuilder` is fine, it has no `spacing:`),
small focused widgets (<150 lines/file), package imports
(`package:theme_flutter/...`), trailing commas, full null safety. Keep
`flutter analyze` clean — it's the gate.

## Commands

- `flutter pub get`
- `flutter analyze` — must be clean.
- Standalone web compile is proven via a consumer's `flutter build web`
  (CRM). A package isn't directly runnable.
