# ThemeFlutter — Coding Standards

This file guides Claude Code when working in this package.

## What this is

`theme_flutter` is a **shared Flutter package** (not an app). It is the
white-label customization **runtime**: it fetches a tenant's resolved branding
from the ThemeService API at startup, disk-caches the last-good copy,
and exposes brand-overridable resolvers (`ThemeColor`, `ThemeImage`,
`ThemeIcon`, `ThemeFont`, `ThemeText`) plus
a set of **showcase** preview screens (`lib/showcase/`).

It was extracted from `../MobileApp/lib/customization/` so two systems can share
it:
- **`../MobileApp`** — the member app; its real screens consume the resolvers,
  and `lib/core/design_constants.dart` is driven by them.
- **`../AppManagement`** — the admin app; its live theme preview renders the
  showcase screens in a phone frame and switches themes via `selectDesign`.

**NOT to be confused with `../ThemeService`** — that is the Python
pipeline that *generates* the configs this package *consumes*. Different system,
different language; the name collision is why this package is
`theme_flutter`.

## Hard rules

- **App-agnostic by construction.** This package must NEVER import from
  `package:mobile_app/...`, `package:app_management/...`, or any app. The only
  app-specific inputs are injected through `ThemeRuntime.initialize`
  (`appId`, `designId`, the six `expected*` slot lists). If you need an app
  constant, add it to `EngineTokens` (engine-internal defaults) or take it as a
  parameter — never reach into a consuming app.
  - Enforce: `grep -rn 'package:mobile_app\|package:app_management' lib` must be
    empty.
- **Brand values resolve LIVE.** Colours/fonts/images/text/icons come
  from the loaded customization via the resolvers; the only hardcoded values are
  the const CombatDen fallbacks (in `EngineTokens` / `ShowcaseTokens`) used when
  nothing is loaded. Resolvers never throw.
- **`ShowcaseTokens` is NOT `DesignConstants`.** It reproduces the member-app
  look for the showcase island. Do not merge it with either app's
  `DesignConstants` (see the comment in `showcase_tokens.dart`).
- **Web-safe.** Both consumers build for Flutter web (AppManagement is web).
  No `dart:io`, no `File`, no `Platform.*`. Verify with a consumer's
  `flutter build web`.
- **Package assets** live in `assets/` and are referenced by consumers as
  `packages/theme_flutter/assets/...` (centralized in
  `lib/showcase/showcase_assets.dart`). Don't require consumers to re-declare
  them.

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
  (AppManagement). A package isn't directly runnable.
