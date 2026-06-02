# LandingPage

The CombatDen marketing site. A **modular** React-via-CDN + Babel-standalone build (no bundler). Two
pages at the repo root — `index.html` (landing, 8 sections) and `pricing.html` — each loads the
modular `.jsx` files under `hifi/` via `<script type="text/babel" src=…>` and renders inside a
`<ThemeProvider>`.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills are living documents

When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new page or section, a renamed module, a changed `COPY` structure, an added dependency, a changed dev-server workflow, a rule the JSX has outgrown on purpose), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## File structure

- `hifi/ds.jsx` — design tokens (`GW`), the `BRAND` name constant, atmosphere primitives (`GWGlow`, `GWDotGrid`) and the `gwRgba` helper.
- `hifi/theme-store.jsx` — the stateful global theme: `THEMES`, the hardcoded `THEME_ASSETS` dict, `ThemeProvider`, `useTheme`, `ThemeSwitcher`.
- `hifi/copy.jsx` — `COPY`: all marketing/section strings (mirrors `contents.md`).
- `hifi/chrome.jsx` — shared chrome: `GWButton`, `GWNav`, `GWDisclaimer`.
- `hifi/footer.jsx` — `FooterSection` (shared by both pages; Google Form POST + Calendly open).
- `hifi/mocks/` — `phone-mock.jsx` (`PhoneFrame` device shell + the theme-driven `PhoneMock`/`GymAppScreen`; the hero defines its own `ScreenshotPhone` around `PhoneFrame` for real screenshots), `theme-preview.jsx` (prop-driven `ThemePreview` card, no longer rendered on the page).
- `hifi/sections/` — one file per section: `hero`, `what-it-is`, `brand`, `feed`, `recs`, `loyalty`, `why`, `pricing-table`.

**Load order matters** — there is no module system; files share globals via `window`. Order is `ds → theme-store → copy → chrome → footer → mocks → sections → inline render`. When you add a file, wire it into the HTML in dependency order (anything it references must load first). Each file ends with `window.X = …` / `Object.assign(window, {…})`.

**Don't move paths.** `deploy/upload.py` uploads root `*.html` (non-recursive), the root single-file globs `robots.txt`, `sitemap.xml`, and `llms.txt`, plus `hifi/**/*` and `assets/**/*`, and excludes `onepager/`. Keep pages at root, JSX under `hifi/`, and any image the JSX references under `assets/` (landing images live in `assets/landing/`). The three root text files (`robots.txt`/`sitemap.xml`/`llms.txt`) are each matched by name, so a NEW root file of another kind would be silently dropped — add its own glob to `INCLUDE_GLOBS` if it must ship. Move any of these and deploy globbing silently drops files.

## Modular, never a mega-file

The page used to be one giant `hifi/landing.jsx`. It isn't anymore, on purpose. Add a section as its own file under `hifi/sections/`, export it to `window`, and wire it into the HTML. Do not grow any single file back into the old mega-file. "Easily editable, not one huge file" is the standing constraint.

## Copy rule (strict) + keep `contents.md` in sync

**No hardcoded marketing strings in section JSX.** Every user-visible headline, subline, button label, placeholder, price, reward, stat, and form string lives in `COPY` (`hifi/copy.jsx`), keyed by section. Sections read from `COPY`.

- **Exception:** illustrative micro-labels baked into a mock's furniture — a status bar "9:41", the agent demo dialogue, a demo file name, "Up next" — stay inline in the mock/visual component. They are part of the picture, not marketing copy.
- **`contents.md` is the marketing source of truth and MUST stay in sync with the live page.** It is important marketing context. Whenever landing copy changes, update BOTH `copy.jsx` (what renders) AND `contents.md` (the record + per-section rationale) in the same change. A stale `contents.md` misleads marketing and breaks this rule.
- Adding visual config (image paths, layout flags) that pairs with copy? Keep it beside the copy entry or in a sibling structure; the page already keeps image paths in components/`THEME_ASSETS`, not buried in prose.
- **No em dashes** in user-visible copy (PRODUCT.md principle). Use a comma, a period, or two sentences. Also avoid `--`.

If you find yourself typing a marketing string literal inside a section, stop and put it in `COPY` first.

## Stateful theme store

`theme-store.jsx` holds a single global active brand theme in React context. It is **not** the product's CustomizationEngine — it's presentation-only: a `THEMES` list plus a hardcoded `THEME_ASSETS` `{ themeId → image/gif }` dict. The theme store is currently **dormant on the live page**: no rendered section consumes `useTheme()` anymore, so switching the active theme has no visible effect. The theme-driven `PhoneMock`/`GymAppScreen` and `ThemeSwitcher` are kept for reuse but are not rendered. The §1 hero now renders a trio of `ScreenshotPhone` frames (rewards · home · videos, sharing `PhoneFrame`) showing **real** screenshots from `assets/landing/screenshots/` (`{screen}-{gym}.png`), cycling all six gyms together every 5s with an opacity crossfade (starting on yoga); the full-res PNGs (~16MB) load progressively via a lazy `seen` set (the incoming gym is preloaded one tick ahead). The §3 brand section is a split layout: copy on the left and, on the right, a transparent looping video (`assets/landing/gymworld-3phones.webm`) of the member app fanned across three brand themes (the phones are baked into the alpha clip); it plays only while in view (see the videos rule below). (The prop-driven `ThemePreview` card component still exists for reuse but is no longer rendered on the landing page.) The §5 recs phone and the §4 feed phone do **not** use the global theme: recs uses static demo assets, and the §4 feed runs its own per-widget state machine on two clocks: the 01 prompt bubble is video-linked (`gym` from the phone video's `currentTime`, 3s/gym), while the lower 02/03/04 grids cycle on a separate slower timer (`gridGym`, 8s hold) unlinked from the video. Both crossfade on change (~1s); thumbnails are real VideoService assets under `assets/landing/feed/` (see `sections/feed.jsx`). If the theme-driven mocks are ever brought back, `THEME_ASSETS` is their image edit point; the hero's screenshots are plain files under `assets/landing/screenshots/` named `{screen}-{gym}.png`.

## Use the impeccable skill for design work

For genuine design work (new sections, visual treatments, a polish pass) use the `impeccable` skill and follow `DESIGN.md`. For a faithful port of an already-approved comp, stay true to the comp rather than re-deriving the look; don't over-apply impeccable's generative ceremony to a port.

## Search the web for conventions before designing

When the design question is "how do good sites usually present X?" — pricing tiers, free trial messaging, plan badges, FAQ layouts, footer structures, signup flows, error states, empty states, billing copy, onboarding patterns — **search the web first.** Look at what proven SaaS companies actually ship (Vercel, Linear, Notion, Stripe, Raycast, Dropbox, etc.). Don't guess.

Why: convention is a usability shortcut. Buyers pattern-match to layouts and copy they've seen elsewhere. Inventing a novel treatment for a normalized thing makes the page feel wrong even if it's "creative." Worse, guessing wastes iteration cycles when the right answer is already publicly documented across a dozen pricing pages.

How to apply:
- If the work is a normalized/conventional pattern, run a WebSearch + WebFetch a couple of real pricing pages before proposing a design.
- Quote the convention you found ("Vercel uses 'Free forever' embedded in the card description; Dropbox uses 'Try for free' as the CTA").
- Then make the call — sometimes the convention is wrong for this product, but you can only know that after seeing it.
- Skip the search for genuinely project-specific work (this product's unique mechanic, our brand voice, internal copy decisions). Convention search is for the parts every SaaS has.

## Dev server: assume it's already running

**Never spawn `serve.py` / `make serve` in the background to smoke-test.** The harness doesn't reliably reap backgrounded processes, and the leftover servers squat on port 4173 — next time the user runs `make serve`, it fails with "port taken" and they have to hunt down PIDs.

Default assumption: the user has `make serve` running in their own terminal. To verify a change, just point them at the URL (`http://localhost:4173/` for the landing, `http://localhost:4173/pricing.html` for pricing).

If you genuinely need the server running (e.g. for a Bash HTTP check), **ask first.** Don't background it yourself. If a smoke-test can be done by checking the filesystem (`ls`, `stat`, Read) instead of HTTP, prefer that.

## Videos play only while in view

**Every `<video>` on the landing page must play only while it is on screen, and restart (reset to the start) when it scrolls out of view.** No clip ever plays off-screen, and a viewer always catches it from the top. This is a standing rule, not a per-section choice.

Don't use the `autoPlay` attribute. Instead attach a ref to the `<video>` and call the shared `useVideoInView(videoRef[, onVisible])` hook from `hifi/ds.jsx` — an IntersectionObserver that calls `play()` on enter and `pause()` + `currentTime = 0` on exit. Keep `loop muted playsInline preload="auto"` on the element. The optional `onVisible(bool)` callback is for callers (like the §4 feed) that also need the in-view state for their own logic. The §3 brand video (`sections/brand.jsx`, transparent alpha clip), the §4 feed phone (`sections/feed.jsx`), and the §5 recs phone (`sections/recs.jsx`) all use it; any new video must too.

**Shared reveal point — `IN_VIEW_MARGIN` (`ds.jsx`).** Scroll-triggered animations must not fire the instant a sliver peeks in. `useVideoInView` and every other scroll-gated animation — the §7 count-up (`why.jsx`), the §6 loyalty loops (`loyalty.jsx`), and the hero gym-cycle (`hero.jsx`) — observe with `rootMargin: IN_VIEW_MARGIN` (a bottom inset of `-25%`), so an element only counts as "in view" once it has scrolled ~25% up into the viewport. It's a bottom `rootMargin`, not an element-ratio `threshold`, on purpose — ratio thresholds misfire on phone mockups taller than the fold. Tune that one constant to move where every animation begins; any new scroll-triggered animation should reuse it. (Exception: the §4 feed's separate `threshold: 0` observer is intentional — it only **preloads thumbnails** ahead of the reveal, it doesn't start playback.)

## Line breaks in copy (\n)

The page root (the `<main>` in `index.html` / `pricing.html`) sets `whiteSpace: "pre-line"`. Because CSS `white-space` is inherited, every `\n` inside a `COPY` string renders as a real line break, while runs of regular spaces still collapse normally. To force a line break in copy, just put `\n` in the string — no `<br />`, no extra wrapper element, no per-element `whiteSpace` override.

If a specific element needs the opposite behavior (e.g. a button label that should never wrap), it must override locally — `whiteSpace: "nowrap"` on the element keeps doing what it always did.
