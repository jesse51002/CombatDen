# ThemeReact — Coding Standards

This file guides Claude Code when working in this package.

## What this is

`theme-react` is the **React mirror of `../ThemeFlutter`**. Two things live here,
and the boundary between them is load-bearing:

- **`src/lib/`** — the white-label theme **runtime**, the library. It fetches a
  tenant's resolved branding from the ThemeService API, keeps a last-good copy
  in `localStorage`, and exposes brand-overridable resolvers. It is
  **runtime + resolvers only** — no screens, no bundled assets. This is the
  package `package.json` describes and what the `dist/` bundles contain.
- **`src/app/`** — the **standalone theme browser**: the public, unauthenticated
  page that pages ThemeService's catalog and previews each design inside a phone
  frame. It is a *consumer* of `src/lib`, exactly as `../../CRM` is a consumer of
  `theme_flutter`.

**NOT to be confused with `..` (ThemeService itself)** — that is the Python
pipeline which *generates* the configs this package *consumes*. Different
language, different toolchain (poetry vs npm); they share only the HTTP contract
that `make api` serves.

## Why it exists alongside ThemeFlutter

The Flutter theme section is welded to the CRM: `theme_flutter` is a path dep of
`../../CRM`, the browsing UI lives in `CRM/lib/features/`, the 7 preview screens
live in `CRM/lib/showcase/`, and `themes.combatden.net` is a second `--target`
of the CRM app rather than a separate app. This package is the same surface with
no Flutter and no CRM.

**Nothing on the Flutter side is being retired.** `theme_flutter`,
`CRM/lib/showcase/`, the CRM admin Theme tab, and the `themes.combatden.net`
build target all stay live. Treat them as read-only from here.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality.
Whenever this package genuinely diverges from what this file says (a changed
export surface, a moved file, a new dependency, a rule the code has outgrown on
purpose), **update this file in the same change** so the doc and the code never
drift apart. Never leave it stale: a stale rule produces false "violation"
findings in review and misleads the next contributor.

## Hard rules

These mirror `../ThemeFlutter/CLAUDE.md`'s own Hard rules, because the two
packages are the same runtime in two languages.

- **The library is app-agnostic by construction.** `src/lib/` must NEVER import
  from `src/app/`. The only app-specific inputs are the arguments passed into
  `ThemeRuntime.initialize` (`appId`, `designId`, the five `expected*` slot
  lists). If you need an app constant, take it as a parameter or add it to
  `EngineTokens` — never reach into the app.
  - **Enforced:** `eslint.config.js` Gate 1. `npm run lint` fails on it.
- **Brand values resolve LIVE.** Colours, fonts, images, text and icons come from
  the loaded theme via the resolvers. The only hardcoded values are the CombatDen
  fallbacks used when nothing has loaded. **Resolvers never throw** — every one
  degrades to its fallback.
- **No bundled assets in the library.** `src/lib/` ships no images. The showcase's
  bundled fallback PNGs live in `src/app/`, which owns them.
- **The two token systems never meet.** The app chrome (`GW` + the CRM's light
  `DesignConstants` values) and the showcase island (`ShowcaseTokens`) share token
  NAMES with different VALUES — `radiusBig` is **12** in the chrome and **32** in
  the showcase. They are separate modules, separate CSS-variable namespaces
  (`--gw-*` / `--adm-*` versus `--sc-*`), and neither imports the other.
  - **Enforced:** `eslint.config.js` Gates 2a and 2b.

## Two things that will bite

- **`letterSpacing` ports as `px`, never `em`.** Flutter's `letterSpacing` is an
  absolute logical pixel value that does NOT scale with font size; CSS `em` does.
  `ShowcaseTokens.h1` is `letterSpacing: -0.02` at 24px → `-0.02px`. Writing
  `-0.02em` gives `-0.48px` — about 24× tighter. The one legitimate `em` is
  `library_card.dart:75`, which writes `0.08 * h3.fontSize` and is explicitly
  proportional.
- **`getSnapshot()` must return a cached reference.** `useSyncExternalStore`
  throws "The result of getSnapshot should be cached" and loops forever if the
  store returns a fresh object literal per call. Build one frozen snapshot inside
  `notify()` and return the same reference until the next change.

## The dev server port is pinned on purpose

`vite.config.ts` pins `:8080` with `strictPort: true`. `../../FastApiBackend`'s
CORS allowlist (`src/core/config.py`) contains `8081`, `8082`, `3000`, `8080` —
but **not** Vite's default `5173`. On any other port
`GET /api/v1/theme/showcase-defaults` fails CORS. Pinning is what keeps this a
zero-backend-change frontend; don't "fix" the port.

## Local dev needs internet unless you opt out

`../src/api/config.py` defaults `assets_cdn_base_url` to `https://cdn.combatden.net`
and `../.env` does not override it — so **even a locally-running ThemeService
returns absolute prod-CDN URLs** for every image and icon. To work fully offline,
set `ASSETS_CDN_BASE_URL=` (empty) in `../.env`; the API then returns relative
paths that `resolveImageUrl` absolutises against `localhost:8001`.

## Dependencies

**npm**, not poetry. Add with `npm install <pkg>` / `npm install -D <pkg>`; the
lockfile is committed. `node_modules/` and `dist/` are gitignored both here and
at the repo root.

Keep the dependency count near zero. The runtime has **no** dependencies beyond
React itself (a peer dep) — the paging, debouncing, animation, and store
primitives are all hand-written precisely because each is ~50 lines and a
dependency is forever. `npm audit` must report **0 vulnerabilities**; that is why
this package emits its own types with `tsc` rather than adding `vite-plugin-dts`.

## Commands

Run from this directory, or from `..` via the `react-*` Makefile targets.

- `npm run dev` — the app on `:8080`. **Needs `cd .. && make api` running.**
- `npm run typecheck` — `tsc -b`. Strict; part of the gate.
- `npm run lint` — eslint, `--max-warnings 0`. Carries the three architecture gates.
- `npm run test` — vitest.
- `npm run build` — app bundle, then the ES + UMD library bundles, then types.

**All four of typecheck / lint / test / build must be clean before committing.**
