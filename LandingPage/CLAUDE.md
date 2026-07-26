# LandingPage

The CombatDen marketing site. A **modular** React-via-CDN + Babel-standalone build (no bundler). Three
pages at the repo root — `index.html` (landing, 8 sections), `ai.html` (the agent layer, 6 sections)
and `pricing.html` — each loads the modular `.jsx` files under `hifi/` via
`<script type="text/babel" src=…>`. `index.html` renders inside a `<ThemeProvider>`; `ai.html` does
not, because nothing it renders consumes the (dormant) theme store.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new page or section, a renamed module, a changed `COPY` structure, an added dependency, a changed dev-server workflow, a rule the JSX has outgrown on purpose), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## File structure

- `hifi/ds.jsx` — design tokens (`GW`), the `BRAND` name constant, atmosphere primitives (`GWGlow`, `GWDotGrid`) and the `gwRgba` helper.
- `hifi/theme-store.jsx` — the stateful global theme: `THEMES`, the hardcoded `THEME_ASSETS` dict, `ThemeProvider`, `useTheme`, `ThemeSwitcher`.
- `hifi/copy.jsx` — `COPY`: all marketing/section strings (mirrors `contents.md`).
- `hifi/chrome.jsx` — shared chrome: `GWButton`, `GWNav`, `GWDisclaimer`.
- `hifi/footer.jsx` — `FooterSection` (shared by all three pages; Google Form POST + Calendly open). Optional `headline` and `background` props: the AI page closes on its own line and needs a transparent footer so its fixed motif layer shows through.
- `hifi/mocks/` — `phone-mock.jsx` (`PhoneFrame` device shell + the theme-driven `PhoneMock`/`GymAppScreen`; the hero defines its own `ScreenshotPhone` around `PhoneFrame` for real screenshots), `theme-preview.jsx` (prop-driven `ThemePreview` card, no longer rendered on the page).
- `hifi/sections/` — one file per section: `hero`, `what-it-is`, `brand`, `feed`, `recs`, `loyalty`, `why`, `pricing-table`, plus the AI page's `ai-hero`, `ai-problem`, `ai-how`, `ai-proof`, `ai-employee`.
- `hifi/motif.js` — the AI page's 3D motif. **The one non-JSX file under `hifi/`**: three.js ships as an ES module, so this loads as `<script type="module">` alongside the Babel bundle instead of through it. It exports `window.CDMotif.init()`, which `ai.html` calls from a `useEffect` after mount, because it measures real section geometry that doesn't exist before the first render. It finds its hosts by data attribute (`[data-motif-hero]`, `[data-motif-section]`), never by class, so sections can be renamed or reordered without touching it.
- `comps/` — standalone design comps and motif studies. **Working files, not pages.** They lived at the repo root while being built, where the non-recursive `*.html` deploy glob *would* have shipped them publicly; `comps/` is out of that glob's reach and is also named in `EXCLUDE_PREFIXES` as a second guard.

**Load order matters** — there is no module system; files share globals via `window`. Order is `ds → theme-store → copy → chrome → footer → mocks → sections → inline render`. When you add a file, wire it into the HTML in dependency order (anything it references must load first). Each file ends with `window.X = …` / `Object.assign(window, {…})`.

**Don't move paths.** Note the deploy glob for pages is **non-recursive root `*.html`**: any new `.html` left at the root ships to the public site, and any page moved into a subdirectory silently stops shipping. `deploy/upload.py` uploads root `*.html` (non-recursive), the root single-file globs `robots.txt`, `sitemap.xml`, and `llms.txt`, plus `hifi/**/*` and `assets/**/*`, and excludes the internal-only `one_pager/` (legacy `onepager/` is also in the guard). Keep pages at root, JSX under `hifi/`, and any image the JSX references under `assets/` (landing images live in `assets/landing/`). The three root text files (`robots.txt`/`sitemap.xml`/`llms.txt`) are each matched by name, so a NEW root file of another kind would be silently dropped — add its own glob to `INCLUDE_GLOBS` if it must ship. Move any of these and deploy globbing silently drops files.

**`one_pager/` is the internal-only print-sheet leave-behind**, never deployed: `one_pager.html` (a static, self-contained 8.5×11in print/PDF sheet ported from the Claude Design comp — Geist fonts, an Export-PDF `window.print()` button, no React/theme/animation), its `img/` screenshots, and `one_pager.md` (the contents record, mirrors `contents.md`). No `INCLUDE_GLOB` matches it today (root `*.html` is non-recursive), and `EXCLUDE_PREFIXES` guards it regardless. Keep it out of the deploy globs.

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

## Mobile responsiveness

The page is responsive via a **JS breakpoint hook, not CSS media queries.** Because every style is an inline `style={{…}}` object, a `<style>`-block `@media` rule can't override one without `!important` — so responsiveness is driven from JS instead.

- **The hook:** `useIsMobile(query = '(max-width: 768px)')` in `hifi/ds.jsx` (exported on `window`, alongside `MOBILE_Q`). It lazy-inits from `window.matchMedia(...).matches` so the **first paint is already correct** (no flash), and subscribes only to the matchMedia `change` event — so a re-render fires **only when the viewport crosses 768px**, never on scroll/resize within a breakpoint. The animated sections (videos, count-up, carousel, hero cycle) drive state via refs + `useEffect(…, [])`, so a breakpoint-cross re-render does not re-run those effects or reset playback.
- **One breakpoint, phone-only:** `max-width: 768px`. There is no separate tablet tier; ≥769px renders the desktop layout unchanged.
- **How sections use it:** a section calls `const isMobile = useIsMobile();` and swaps a few values — typically `gridTemplateColumns: isMobile ? '1fr' : '<existing>'` and tighter side padding (`20px` instead of `32px`). When adding a section or a multi-column layout, do the same: collapse to a single column on mobile and verify no horizontal overflow at 375px.
- **Non-trivial mobile treatments (don't regress these):**
  - **Nav (`chrome.jsx`):** mobile renders logo + a hamburger button that toggles a dropdown panel of `COPY.nav.links` + the CTA; the bar goes solid while the menu is open, and leaving mobile closes it. Desktop keeps the inline link row.
  - **Hero (`hero.jsx`):** the 3-phone overlapping trio is **kept on mobile but scaled down** (phone widths + negative-margin overlap shrink proportionally) so all three still fit a phone screen instead of clipping.
  - **Loyalty (`loyalty.jsx`):** the points-loop step/icon/arrow sizes shrink so 4 steps + 3 arrows fit a phone; the reward carousel's card width (`CW`) and `sideOffset` are computed from `isMobile` and the card width is passed to `RewardCard` via the `w` prop (it no longer hard-reads the module `CARD_W`).
  - **Pricing (`pricing-table.jsx`):** mobile renders `StackedTiers` (one card per tier, transposing `rows`/`vals`) instead of the wide comparison `<table>`, so there's no sideways scroll.

## Line breaks in copy (\n)

The page root (the `<main>` in `index.html` / `pricing.html`) sets `whiteSpace: "pre-line"`. Because CSS `white-space` is inherited, every `\n` inside a `COPY` string renders as a real line break, while runs of regular spaces still collapse normally. To force a line break in copy, just put `\n` in the string — no `<br />`, no extra wrapper element, no per-element `whiteSpace` override.

If a specific element needs the opposite behavior (e.g. a button label that should never wrap), it must override locally — `whiteSpace: "nowrap"` on the element keeps doing what it always did.
