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

  Its layout mirrors `../ThemeFlutter/lib/` one-to-one, and every file names the
  Dart file it ports from in its header:

  | here | ThemeFlutter |
  | --- | --- |
  | `runtime.ts` | `customization_runtime.dart` |
  | `store/themeStore.ts`, `store/locator.ts` | `customization_service.dart`, `service_locator.dart` |
  | `store/stylesPager.ts` | `data/styles_pager.dart` |
  | `store/persistence.ts` | the `SharedPreferences` half of `customization_service.dart` |
  | `api/client.ts` | `data/customization_api_client.dart` |
  | `models/` | `data/models/*.dart` |
  | `theme/resolvers.ts` | `theme/theme_{color,image,font,text,icon}.dart` |
  | `theme/color.ts` | `dart:ui`'s `Color` |
  | `theme/{themeDerivation,engineTokens,assetWarmer,fontLoader}.ts` | the matching `theme/*.dart` |
  | `react/` | *(no counterpart — Flutter uses `ListenableBuilder`)* |
  | `motion/` | `theme/animation/*.dart` |

  `src/lib/index.ts` is the ONLY export surface; nothing else is importable.

  **`models/themeFontFace.ts` ports nothing, and `ThemeConfig` carries three
  fields the Dart one does not** — `category`, `fontFaces` and
  `imageComplexity`. All three come off wire sections ThemeFlutter's
  `ThemeConfig.fromJson` never reads (`category`, `font_set`, `image_set`),
  because Flutter needs only a family name to call `GoogleFonts.getFont` and
  only a URL to fetch an image. This runtime reads them because `src/app/`'s
  artifact inspector renders the pipeline's own reasoning, which nothing on
  the Flutter side does. The divergence is additive: every field the Dart
  model has, this one still has, parsed the same lossy-tolerant way.
- **`src/app/`** — the **standalone theme browser**: the public, unauthenticated
  page that pages ThemeService's catalog and previews each design inside a phone
  frame. It is a *consumer* of `src/lib`, exactly as `../../CRM` is a consumer of
  `theme_flutter`.

  Like the library, it is a PORT — of the CRM's theme surfaces and the landing
  page's chrome — and every file names the Dart (or JSX) file it ports from in
  its header:

  | here | ports |
  | --- | --- |
  | `tokens/gw.ts`, `chrome/` | `LandingPage/hifi/{ds,chrome,copy}.jsx` |
  | `tokens/adminTokens.ts` | `CRM/lib/core/constants/design_constants.dart`, LIGHT half only |
  | `browser/ThemeBrowser.tsx` | `.../member_app/theme_tab/live_theme_preview_tab.dart` |
  | `browser/Library{View,Card}.tsx` | `.../themes_library/library_{view,card}.dart` |
  | `browser/Theme{Grid,Card,SearchBar,PreviewPane}.tsx` | the matching `.../theme_tab/theme_*.dart` |
  | `browser/selectedStyle.ts` | the THEME half of `CRM/lib/core/state/selected_gym.dart` |
  | `widgets/` | `CRM/lib/shared/widgets/*.dart` |
  | `showcase/` | `CRM/lib/showcase/` |
  | `showcase/celebrations/CountUpText.tsx` | `CRM/lib/shared/widgets/animation/count_up_text.dart` |
  | `showcase/celebrations/CelebrationFrame.tsx` | `MobileApp/lib/shared/widgets/post_class/{post_class_scaffold,layouts/celebration_*}.dart` |
  | `showcase/videos/` | `MobileApp/lib/features/videos/` + `.../shared/widgets/video_recc_card/` |
  | `showcase/profile/` | `MobileApp/lib/features/profile/` |
  | `showcase/classdetail/` | `MobileApp/lib/features/class_booking/presentation/` (`ClassScreen`, NOT `ClassBookedScreen`) |
  | `showcase/showcaseVideoDefaults.ts` | *(no counterpart — constants extracted from `VideoService/videos/*.yaml`)* |

  Four things port NOTHING, because the Flutter side has no counterpart to
  port: `appUrl.ts` (the CRM's theme surface is a single tab, so it never had a
  top-level view switcher), `ViewTabs.tsx` (that switcher), `inspect/` (the
  artifact inspector) and `studio/` (the generation studio). They are native,
  and they still obey every rule below — the chrome's tokens, the lint gates and
  the React Compiler constraints.

  The count-up is the one file in `showcase/` that does not come out of
  `CRM/lib/showcase/`. Dart keeps it in `shared/widgets/animation/` because the
  kiosk uses it too; this app has no kiosk, and its only readers are the
  celebration screens — so it sits with the other celebration primitives rather
  than in a one-file `animation/` folder.

  **`showcase/videos/`, `showcase/profile/` and `showcase/classdetail/` port
  from `MobileApp/`, not from `CRM/lib/showcase/`.** The Flutter preview carries
  seven screens and has no Video, Profile or class-detail clone to copy, so
  those three are first ports straight from the member app; every file in them
  names the `MobileApp/` file it comes from, and anything they need that the CRM
  clone never had (the two profile belt PNGs in `showcase/assets/`, the static
  map tile in `showcase/classdetail/assets/`) comes from `MobileApp/assets/` for
  the same reason. If the Flutter preview ever grows its own clones, these stay
  the port of record — they are ahead of it, not behind.

  The class-detail map is `classdetail/assets/`, not the shared
  `showcase/assets/` + `showcaseAssets.ts` registry, because exactly one screen
  reads it. Fold it into the registry if a second one ever does.

  Nothing gated on `selectedGym.gymId != null` ports: this browser has no gym,
  no auth and no write path, so the admin's "set as app theme" / "edit gym name"
  actions and the gym-identity plumbing are deliberately absent, not missing.

### The ten showcase screens

`showcase/showcaseScreen.tsx` is the registry, and adding a screen touches four
compiler-linked spots in it: the `ShowcaseScreen` union, the frozen
`SHOWCASE_SCREENS` array (slideshow order), `SHOWCASE_SCREEN_LABELS`, and the
exhaustive switch. Consumers (`browser/ThemePreviewPane.tsx`) derive their chips
and arrows from those arrays and need no change.

| screen | label | shape | body scrolls |
| --- | --- | --- | --- |
| `home` | Home | app surface | **yes** |
| `class` | Class | app surface | **per arrangement** |
| `booking` | Booking | celebration (loops) | no |
| `wins` | Achievements | celebration (loops) | no |
| `points` | Points | celebration (loops) | no |
| `rewards` | Rewards | celebration (loops) | no |
| `streak` | Streak | celebration (loops) | no |
| `store` | Store | app surface | **yes** |
| `video` | Video | app surface | **yes** |
| `profile` | Profile | app surface | **yes** |

That split is a rule, not a coincidence. An **app surface** is a screen a member
scrolls on a real device, so clipping it previews a shorter app than the one
being licensed. A **celebration** is a single-moment composition: a post-class
reward animation is not a scrolling surface, and giving one a scrollbar would
invent a behaviour the member app does not have. Both kinds are rearranged by a
`*_format` slot (below); neither may earn its arrangement by scrolling.

### The celebration cards share ONE arrangement

`wins`, `points`, `rewards` and `streak` are the post-class cards, and the
pipeline classifies all four with a single slot — `celebration_format`, whose
own doc says "the body slot differs per card, the arrangement around it does
not". So the hook lives in **`showcase/celebrations/CelebrationFrame.tsx`**, the
port of `PostClassScaffold` and its five layouts, and the four screens compose
into it. One choice moves all four, and `showcase/showcaseScreen.tsx` — the file
all four are registered in — never learns the slot exists.

Two things about that set are easy to get wrong. The member app has a **fifth**
consumer, `rank_screen.dart`; the Flutter preview this island ports never
carried a rank celebration, so there is no rank card here to rearrange. And
`BookingShowcase` is **not** one of them — it clones `ClassBookedScreen`, which
is governed by **no format slot at all** (see the section below).

The member app's layouts arrange four slots (header, body, close, one primary
action); a preview card ships exactly one, its **body**, so the frame places
exactly that one and never invents an action to arrange. What the absent action
leaves behind is a measurement: `splitBand` and `fullBleed` still reserve
`kCelebrationCtaZone` beneath the celebration, because both values ARE the seam
between the card and the canvas the action stands on.
`showcase/__tests__/celebrationFormats.test.tsx` is the mechanical gate — the
stage's subtree must come out byte-identical across all five values, per card,
in both of each card's views.

### `class` and `booking` are two different screens

The single easiest mistake in this island, because both port out of the Dart's
one `features/class_booking/` folder and both have "booking" in the name.

- **`class`** (`showcase/classdetail/`) ports **`ClassScreen`** — the class
  DETAIL page: topbar + back, photo, meta, details, instructor, location, and
  exactly one reserve action. It is the **only** consumer of `class_format`;
  `ThemeLayout.classDetail()` is read in exactly one place on the Dart side,
  `class_screen.dart`.
- **`booking`** (`showcase/BookingShowcase.tsx`) clones **`ClassBookedScreen`** —
  the post-reservation CELEBRATION: image scale-pop, caption cascade, CTA fade,
  then a hold and a replay. It is routed at `AppRoutes.reservingLoading`, reads
  **no** format slot, and is not a `celebration_format` card either (that slot
  belongs to `post_class/`, which backs `wins`/`points`/`rewards`/`streak`).

So `class_format` never had a surface in this package until `classdetail/` was
built, and `booking` must never be reshaped into a detail page — doing so would
delete the looping animation the preview run depends on.

`class` is the only screen whose scrolling is **per arrangement** rather than
per screen: each of the five layouts owns its own scroller exactly as the Dart's
five do, so `ClassDetailShowcase` passes no `bodyScroll` and `ShowcaseScaffold`
stays `overflow: hidden`. That is what keeps `detailSheet`'s full-bleed backdrop
from being clipped by an ancestor scroller it never asked for.

Its section folder is `showcase/classdetail/sections/`, where the Dart says
`widgets/`: Gate 2a bans `**/widgets/**` anywhere in this island and matches the
IMPORT STRING, so `../widgets/ClassMetaSection` trips it even pointing at the
screen's own folder.

`showcase/showcaseSlots.ts` is a SUBSET of the member app's manifest — only what
these screens render. `next_rank_belt_image` is in it because `profile` renders
it (`showcase/profile/NextRankSection.tsx`); it is the pipeline's tenth
generated image, derived from `rank_belt`, and Profile is its only consumer in
the member app too. `reserve_cta` was in it from the start and rendered by
nothing until `class` arrived — `showcase/classdetail/sections/
ClassReserveFooter.tsx` is its first consumer here.

The demo CONTENT ladder is `showcase/useShowcaseContent.ts`: classes and rewards
resolve real → fetched (`GET /theme/showcase-defaults`) → bundled
(`showcaseGroupDefaults.ts`), and video feeds resolve real → bundled
(`showcaseVideoDefaults.ts`) because the wire format carries no videos. Videos
deliberately skip `fillSlots` — that helper repeats a single item across a FIXED
four-card layout, and a feed has no slots to fill.

**That ladder picks ONE TIER for the whole class list, which is why the class
detail screen resolves three of its fields per-FIELD instead.** A
`ShowcaseClassInfo` carries `description`, `instructorBio` and
`instructorImageUrl` as OPTIONAL — the bundled tier has all three for every
group (extracted from `VideoService/gyms/*.yaml`, which is also where the rest
of that file came from), and the fetched tier declares them (`str | None` on
`FastApiBackend/src/theme/schema/theme_schema.py`) but serves NULL for every
one, because its source
`FastApiBackend/src/theme/showcase_defaults/theme_showcase_defaults.yaml` was
ported from the CRM constants that predate the fields, and says so in its own
header. A per-tier ladder therefore lets the fetched nulls hide the richer
bundled copy whenever `:8000` is up. `showcase/classdetail/classDetail.ts`
closes that by filling each missing field from the bundled class of the same
name; the real fix is for that yaml to carry them.

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
  `initializeTheme` / `<ThemeProvider>` (`appId`, `designId`, the five
  `expected*` slot lists). If you need an app constant, take it as a parameter
  or add it to `EngineTokens` — never reach into the app.
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
  - **Enforced:** `eslint.config.js` Gates 2a and 2b. Those gates match the
    IMPORT STRING, so a token module's filename is part of the enforcement —
    rename one and add the new spelling to the gate in the same change.
- **The chrome's tokens live twice, and the test keeps them honest.**
  `src/app/tokens/` is the source of truth (the ported `GWNav` / `GWButton` keep
  their verbatim inline `style={{}}` objects and read it directly);
  `src/app/styles/tokens.css` republishes the same values as CSS variables for
  every CSS Module. `src/app/__tests__/tokens.test.ts` parses the sheet and
  fails if the two drift.

## `<ThemeProvider>` is a gate, not a value carrier

The store is a **module singleton**, exactly as `get_it` is on the Flutter side.
The theme does NOT flow down through React context: every hook reads the
singleton through `useSyncExternalStore`. `<ThemeProvider>` does exactly two
things — kick `initializeTheme` and hold its children back until the bootstrap
settles (the analogue of the `FutureBuilder` in CRM's
`live_theme_preview_tab.dart`).

That is deliberate, and it is what lets the **non-hook resolvers**
(`themeColor`, `themeToken`, `themeText`, `themeImageSrc`, …) work identically
outside a component — which a token module needs. If you find yourself adding a
context so a value can reach somewhere, the resolver already reaches there.

## Things that will bite

- **The wire's flat `images` / `fonts` / `icons` maps are FROZEN at
  `slot -> string`, and widening one breaks the Flutter clients silently.**
  Both runtimes parse them with a helper that SKIPS any entry whose value is
  not a bare string (`parseStringMap` here, `_parseStringMap` in
  `../ThemeFlutter`), so turning `fonts` into `slot -> {family, …}` would not
  raise anywhere — the CRM and the member app would take a 200 with an empty
  font map and fall back to their bundled faces. New per-slot metadata
  therefore arrives on a GROUP beside the flat map (`font_set` passes the
  artifact's own group through; `image_set` is projected because
  `ImageOutput` carries a server path and a prompt), and the flat map stays a
  projection of it. `parseThemeConfig` reads both: the family/URL off the
  flat map, the metadata off the group, so a `localStorage` last-good copy
  written before a group existed still resolves everything it ever did.
- **`letterSpacing` ports as `px`, never `em`.** Flutter's `letterSpacing` is an
  absolute logical pixel value that does NOT scale with font size; CSS `em` does.
  `ShowcaseTokens.h1` is `letterSpacing: -0.02` at 24px → `-0.02px`. Writing
  `-0.02em` gives `-0.48px` — about 24× tighter. **`em` is legitimate only where
  the Dart itself writes the value as a fraction of `fontSize`**, which is a
  proportion by construction and therefore ports as one: `library_card.dart:75`
  (`0.08 * h3.fontSize`), `rewards/RewardBandSection.module.css` (`0.16 *
  h3.fontSize`) and `rewards/SparkleHero.module.css` (`0.24 *`). Anywhere the
  Dart writes a bare number, it is logical pixels and `em` is a bug.
- **`getSnapshot()` must return a cached reference.** `useSyncExternalStore`
  throws "The result of getSnapshot should be cached" and loops forever if the
  store returns a fresh object literal per call. Build one frozen snapshot inside
  `notify()` and return the same reference until the next change. Both
  `ThemeStore` and `StylesPager` do; `src/lib/__tests__/themeStore.test.ts` and
  `stylesPager.test.ts` each pin it.
- **`eslint-plugin-react-hooks` v7 turns on the React Compiler rules, and
  `--max-warnings 0` makes every one of them fatal.** `set-state-in-effect`,
  `set-state-in-render`, `refs` (no ref writes during render) and `purity` are
  all errors here, so three familiar patterns are unavailable: writing a ref in
  the render body, `setState` in an effect to reset derived state, and adjusting
  state during render. The replacements this package uses are a lazy
  `useState(() => new Thing())` initialiser (`useStylesPager`), a `key` remount
  to reset (`ThemedImage`), and a **ref callback** wherever Dart reaches for
  `addPostFrameCallback` or a `GlobalKey` — it fires at commit with the node in
  hand, so it may write a ref and measure/scroll (`useElementSize`, the
  centre-once anchors in `LibraryView` / `ThemeGrid`).
- **Flutter's named `Curves.*` are cubic BÉZIERS, not the analytic easings the
  web reaches for, and `Curve.transform` short-circuits both endpoints.**
  `Curves.easeOutExpo` is `Cubic(0.19, 1, 0.22, 1)` — not `1 - 2^(-10t)` — and
  the two diverge visibly over a 1400ms count-up. `showcase/celebrations/curves.ts`
  therefore ports `Cubic.transformInternal`'s own bisection, and CSS needs none
  of it because `cubic-bezier()` IS the same curve (which is why the library
  exports `EASE_OUT_QUART` as a string). The endpoint short-circuit is
  load-bearing, not an optimisation: the bisection stops within
  `_cubicErrorBound` (0.001) of the target x, so without it an ease answers
  ~0.005 at `t == 0` and a phase that has not started is already 0.5% in.
- **CSS scroll anchoring fights a collapsing header.** The library's title
  collapses out of the flow as the page scrolls; Chrome compensates for that
  height change by moving the scroll offset, which shoves it straight back
  across the collapse threshold and flickers. `src/app/styles/base.css` turns
  anchoring off for the document, and that line is load-bearing — the Flutter
  original cannot hit this because its collapsing chrome sits OUTSIDE the
  scrollable.
- **A sticky design selection OUTRANKS the `?theme=` deep link, and each view
  has to correct it for itself.** `ThemeStore.initialize` resolves the design as
  `readSelectedDesignId() ?? <the id the provider was constructed with>`, so a
  pick from a previous visit wins over the URL. `ThemeBrowser` has always
  corrected that with a mount effect (`selectDesign(INITIAL_URL_THEME)`), but it
  only mounts on the library view — so `?view=inspect&theme=X` silently rendered
  the visitor's last pick instead of `X` until `inspect/InspectView.tsx` grew the
  same effect. Two rules follow. A NEW top-level view needs that correction too.
  And the correction must **consume** `INITIAL_URL_THEME` once per page load
  rather than re-reading it on every mount, or returning to the view throws away
  the theme the visitor picked in this session. The duplication is a smell: the
  right home is one effect in `App.tsx`, above every view.
- **Anything the app renders between `GWNav` and `<main>` is a pixel the phone
  view overflows by.** `browser/ThemeBrowser.module.css` sizes phone mode as
  `100dvh - --phone-chrome-height - --app-bottom-gutter`, and
  `--phone-chrome-height` counts ONLY the landing nav (`navHeight + 1px`). The
  view-switcher band `ViewTabs` sits in that gap and is not in the calc, so the
  browse view currently grows a 48px scrollbar in the one mode designed never to
  scroll. `ViewTabs.module.css` publishes its height globally as
  `--app-viewtabs-height` so the fix is one term in that `calc`, not a
  re-measured literal — and so the band's height stays a deliberate contract
  rather than whatever the styling happened to produce.
- **`overflow-y: auto` also makes a box clip HORIZONTALLY, which is why showcase
  scrolling is opt-in per screen.** When one of `overflow-x` / `overflow-y` is
  `visible` and the other is not, the `visible` one COMPUTES to `auto` — so a
  global "make the phone body scroll" would have cropped every surface that
  paints outside its box on purpose (`showcase/celebrations/SparkleBurst.tsx`,
  the `RewardsCarousel` cover flow, `showcase/rewards/SparkleHero.tsx`'s
  scatter). `ShowcaseScaffold` therefore takes a `bodyScroll` prop that only the
  four app surfaces pass, and `.bodyScroll` writes `overflow-x: hidden`
  EXPLICITLY rather than leaving it at `visible` — the difference between a clip
  and a second, sideways scrollbar the screen never uses. It also hides the
  scrollbar (`scrollbar-width: none` + the WebKit pseudo-element): a desktop
  track drawn down the inside of a phone mock is the one detail that gives away
  that this is not a device, and iOS's overlay bar occupies no layout.
- **A `.css` import returns `''` under vitest, `?raw` included.** `test.css`
  defaults to false, so the CSS plugin hands back an empty module and an
  assertion against it passes vacuously. `src/app/__tests__/tokens.test.ts`
  reads the sheet off disk with `node:fs` instead.
- **An app test is typechecked by `tsconfig.app.json`, not `tsconfig.test.json`.**
  The test project reaches its subject through a project REFERENCE, which
  resolves via emitted declarations, and the app project is `noEmit` — so an app
  test there fails with TS6307. `tsconfig.test.json` excludes `src/app/**` for
  that reason; the app project's own `include` already covers them.

## The dev server port is pinned on purpose

`vite.config.ts` pins `:8080` with `strictPort: true`. `../../FastApiBackend`'s
CORS allowlist (`src/core/config.py`) contains `8081`, `8082`, `3000`, `8080` —
but **not** Vite's default `5173`. On any other port
`GET /api/v1/theme/showcase-defaults` fails CORS. Pinning is what keeps this a
zero-backend-change frontend; don't "fix" the port.

## Three backends, and only two of them ship

- **`:8001` — ThemeService's read API** (`cd .. && make api`). Finished themes.
  Deployed. Every view needs it.
- **`:8000` — FastApiBackend.** One public call, `showcase-defaults`, for the
  phone preview's demo classes and rewards.
- **`:8002` — ThemeService's STUDIO** (`cd .. && make studio`), bound to
  127.0.0.1 and never deployed. Only `?view=studio` talks to it: launch a run,
  stream its progress, read a finished image mid-run.

`src/lib/config.ts` resolves the first two through an override → Vite env →
default ladder. **The studio's base URL is resolved in `src/app/studio/`
instead, not there** — `src/lib/` is the runtime a consumer installs, and a
laptop-only tool that spends money starting generation runs has no business in
a published package. The ladder is mirrored, not imported, on purpose.

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
- `npm run test` — vitest, configured by `vitest.config.ts` (kept separate from
  the app's `vite.config.ts`). Runs on **jsdom**, because the fallback ladder is
  defined in terms of `localStorage` and the asset warmer in terms of `Image`.
  `src/lib/__tests__/setup.ts` installs an in-memory `Storage` when the
  environment's is unusable — Node 22+ ships its own `globalThis.localStorage`
  that is `undefined` without `--localstorage-file` and shadows jsdom's.
- `npm run build` — app bundle, then the ES + UMD library bundles, then types.

**All four of typecheck / lint / test / build must be clean before committing.**
