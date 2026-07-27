# ThemeReact

The white-label theme runtime for the web, plus the standalone theme browser.
The React mirror of [`../ThemeFlutter`](../ThemeFlutter).

Two things live in one package:

| Path | What |
|---|---|
| `src/lib/` | **The library** (`theme-react`). Fetches a tenant's resolved branding from the ThemeService API, keeps a last-good copy in `localStorage`, exposes resolvers that never throw. No screens, no bundled assets. |
| `src/app/` | **The standalone theme browser.** The public page that pages the catalog and previews each design in a phone frame. A consumer of `src/lib`, exactly as the CRM is a consumer of `theme_flutter`. |

## Status

**Scaffold.** The toolchain, the library/app split, the architecture gates, and
the build outputs are in place and verified. The runtime, the resolvers, the
browsing UI, and the 7 preview screens are not built yet.

## Running it

The API must be up first — nothing renders without it:

```bash
cd ..                  # ThemeService/
make api               # :8001

cd ThemeReact
npm install
npm run dev            # :8080
```

`:8080` is pinned deliberately. `FastApiBackend`'s CORS allowlist contains
`8080` but not Vite's default `5173`, so the one backend read this app makes
(`GET /api/v1/theme/showcase-defaults`, public) would fail CORS on any other
port. See `vite.config.ts`.

From `ThemeService/` there are Makefile shortcuts: `make react-install`,
`make react-dev`, `make react-build`, `make react-check`.

### Offline

Local dev reaches `cdn.combatden.net` for images and icons even with a local
API, because `../src/api/config.py` defaults `assets_cdn_base_url` to the prod
CDN. To work fully offline, set `ASSETS_CDN_BASE_URL=` (empty) in `../.env` —
the API then returns relative paths this client absolutises against
`localhost:8001`.

### Configuration

Both base URLs have working localhost defaults, so no `.env` is needed. See
`.env.example` to point at something else.

## Checks

All four must be clean before committing:

```bash
npm run typecheck      # tsc -b, strict
npm run lint           # eslint --max-warnings 0
npm run test           # vitest
npm run build          # app bundle + ES/UMD library bundles + types
```

`npm run lint` carries three architecture gates that fail the build rather than
drifting:

1. `src/lib/` may not import from `src/app/` — the library is app-agnostic.
2. `src/app/showcase/` may not import the app-chrome tokens.
3. The app chrome may not import `ShowcaseTokens`.

Gates 2 and 3 exist because the two token systems share names with different
values: `radiusBig` is 12 in the chrome and 32 in the showcase.

## Build outputs

```
dist/app/                  the standalone browser (static)
dist/theme-react.js        library, ES module
dist/theme-react.umd.js    library, UMD global `ThemeReact`
dist/types/index.d.ts      types
```

The UMD bundle exists so the bundler-less
[LandingPage](../../LandingPage) (React via CDN + Babel standalone) can
`<script>`-load the library without adopting a build step. React and ReactDOM
are external in both formats.

## Relationship to the Flutter side

Nothing on the Flutter side is retired. `theme_flutter`, `CRM/lib/showcase/`,
the CRM admin Theme tab, and the `themes.combatden.net` build target all stay
live; this package is additive. The Flutter build is also the reference for
verifying this port — run `cd ../../CRM && make run-themes` (`:8082`) beside
`npm run dev` (`:8080`) and compare.
