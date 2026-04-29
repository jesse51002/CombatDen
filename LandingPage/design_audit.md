# Landing page design audit (CombatDen)

Reviewed live on `localhost:4173` (via `make serve`), cross-referenced against `hifi/landing.jsx`. Branch: `main`. Date: 2026-04-29.

Screenshots saved to `.gstack/design-reports/screenshots/` (full-page, fold desktop, fold mobile, per-section).

---

## First impression

The site **communicates competence and a clear vertical**. Black + warm orange (`#FF6C2D`) with a Jura logo says "fight gyms, not generic SaaS." The headline — *"A member app that stops fighters from quitting."* — is specific, benefit-driven, and names the buyer's actual pain. That alone puts you ahead of 90% of fitness SaaS landing pages, which all sound like "Welcome to the all-in-one platform for…"

What stands out positively:
- **Brand is unmistakable** in the first viewport. Combat sports, not generic gym, not generic SaaS.
- **One job per section** is mostly respected. Hero → How it works → Loyalty → Branded → Why it matters → FAQ → CTA. Clean spine.
- **Real warm-neutral background** (`rgb(18,22,25)`) instead of flat `#000`. Off-white text (`rgb(244,243,238)`) instead of pure white. Whoever set up the color tokens cared about dark-mode craft. Surfaces use elevation (`rgb(10,12,14)` → `rgb(26,31,35)`), not just color inversion.
- **Eyebrow → headline → body** rhythm is consistent across sections (eyebrow uppercase orange Jura, headline Inter 600, body Inter 400 muted).
- **Real concrete copy** in the loyalty section (1500pts ≈ 15 classes, $20 shirt = 7× ROI math in FAQ). Not AI-slop copy — that's a founder who knows the unit economics.

The first 3 things my eye goes to: COMBAT DEN logo (orange) → "Book a demo →" pill (orange) → "FOR COMBAT SPORTS GYMS" eyebrow + headline (orange + bone). Hierarchy is intentional. Eye knows what to do.

If I had to describe this in one word: **opinionated**. Which is what you want.

What hurts:
- **Above the fold is half-empty.** At a 1280×720 viewport (the most common desktop), the headline gets cut mid-sentence ("...stops fighters" visible, "from quitting." below). The hero CTA is fully below the fold. You're spending the most expensive real estate on the page on decorative orbital arc lines and vertical breathing room.
- **"Why it matters" is a real bug, not just a polish issue.** The two big stats animate from 0 → 7 and 0 → 9 driven by scroll. If a user lands on `/#why`, anchor-jumps there, scrolls fast, or has slow JS execution, they read **"0× cheaper to keep a member"** and **"$0k more a year from keeping 5% more members."** That's the literal opposite of the message. (Source: `hifi/landing.jsx:2877-2878`.)
- **Babel-standalone is running in production.** Browser-side JSX transformation. Huge JS payload, slow TTI on real networks. Localhost shows 177ms total because nothing has to traverse a wire. Real visitors will not get that.
- **Two unstyled `<a href="#top">` anchors render as default browser blue (`rgb(0,0,238)`).** Not visible because they're empty-text wrapper links, but their existence in the DOM means default link styling is leaking somewhere. Smells.

---

## Inferred design system

| Token | Value | Note |
|---|---|---|
| Background ink | `rgb(18,22,25)` (warm near-black) | ✅ Intentional, not flat #000 |
| Foreground bone | `rgb(244,243,238)` | ✅ Off-white, correct for dark mode |
| Accent orange | `rgb(255,108,45)` | ✅ Distinctive, fits brand |
| Surface elevations | 10,12,14 / 15,19,22 / 26,31,35 | ✅ Real elevation, not lazy |
| Mid gray text | `rgb(138,143,150)` | ✅ Reasonable secondary |
| **Stray default blue** | `rgb(0,0,238)` | ❌ Two empty `<a href="#top">` |
| **Stray Times New Roman** | font-family list | ❌ Default leaking somewhere |
| Display font | Jura 700 | ✅ Logo + numerical stats; geometric/techy |
| Body + heading font | Inter 400/600/700 | ✅ Single workhorse |
| Heading scale | 104 / 80 / 72 / 56 / 48 / 44 / 36 / 26 px | ⚠️ Wide range, mostly intentional but "Reward Examples" at 36 feels weak |
| Body | 16px Inter | ✅ Meets minimum |
| Page height | 9476px | ⚠️ Long; some sections breathe more than they need to |
| Load (localhost) | 177ms | Meaningless — Babel-in-browser will dominate real perf |

**Font over-declaration:** the page declares 7 weights of Inter (300/400/500/600/700) and 4 weights of Jura (400/500/600/700) but only 4 weights ever load (Inter 400, 600, 700, Jura 700). Over-declaration costs nothing on CDN-cached fonts but signals copy-paste rather than a curated stack.

---

## Findings (bucketed by impact)

### High impact

**FINDING-001 — Above-the-fold real estate wasted.**
At 1280×720 (and any viewport ≤900px tall), the hero headline cuts mid-sentence and the orange CTA button lives below the fold. Cause: `heroMinH: 820` + `heroPad: "160px 64px 200px"` (`hifi/landing.jsx:218-219`). The 160 top + 200 bottom padding pushes everything off-screen on a typical desktop. The orbital arcs then feel like atmosphere on an empty stage instead of supporting hierarchy.
**Fix:** tighten the desktop hero — `heroMinH: calc(100svh - 80px)` (or 700px), `heroPad: "120px 64px 80px"`. The headline + tagline + CTA need to fit in the first viewport, full stop. This is the single highest-leverage change on the page.

**FINDING-002 — "Why it matters" stats start at 0 and animate up.**
`hifi/landing.jsx:2877-2878` computes `num1 = (7 * eased)` and `num2 = (9 * eased)`. Eased starts at 0. Anyone hitting `/#why` directly or scrolling fast reads "0×" and "$0k" — the inverse message. The animation is also a nice-to-have, not a feature; you're risking your one numeric proof point for a small motion flourish.
**Fix:** either (a) drop the animation and render the final values directly, or (b) use IntersectionObserver to start the count when the section enters view AND set the initial values to the final ones (so SSR / no-JS fallback shows real numbers, JS replaces with animated count from final-back). Recommended: option (a) — simpler, no edge cases. Two lines.

**FINDING-003 — Babel-standalone in production.**
Console warning: *"You are using the in-browser Babel transformer. Be sure to precompile your scripts for production."* This is ~750KB of Babel + runtime JSX compilation on every page load. On a real network this is going to cost 1-3s of TTI and probably a Lighthouse score in the 40s on mobile. For a marketing site selling to gym owners (who are not patient), this matters.
**Fix:** scope is bigger than a /design-review fix loop — needs a real build step (Vite or esbuild). Out of scope here. **Flag and decide separately.** Punt-cost is real but you have one customer; if you're shipping more pages and want to reach scale, do this before your next major launch.

**FINDING-004 — No `prefers-reduced-motion` honored.**
Confirmed via `grep`: zero references to `prefers-reduced-motion` in `landing.jsx`. The orbital arcs RAF-animate, the WhyItMatters counter scroll-eases, the loop sequence auto-advances every 7s, and the sticky scroll choreography in `HowItWorks` / `DualBenefit` runs regardless. For motion-sensitive visitors this is at minimum uncomfortable, at worst nausea-inducing. Also fails one of the universal design rules.
**Fix:** wrap motion-driven blocks in a `useReducedMotion` hook (`window.matchMedia('(prefers-reduced-motion: reduce)').matches`) and short-circuit to static layouts when true. Single helper, ~30 lines of integration.

### Medium impact

**FINDING-005 — Two unstyled anchors render as default browser blue.**
`document.querySelectorAll('a')` filtered to `color === 'rgb(0, 0, 238)'` returns two `<a href="#top">` with empty text content inside `<div>` parents. They're invisible to a sighted user but they're real DOM and they say "default styles are leaking." Probably the brand-mark-as-home-link wrappers around the COMBAT DEN logo.
**Fix:** locate via `grep -n 'href="#top"' hifi/landing.jsx`, add `color: 'inherit', textDecoration: 'none'` to their inline style. 30 seconds.

**FINDING-006 — Times New Roman appears in computed font-family list.**
Some element falls back to default serif. Could be the same blue-link issue (default-styled element), or a stray un-fontified node.
**Fix:** find and kill once FINDING-005 is fixed; if it persists, `grep -nE "fontFamily" hifi/landing.jsx` to see if any element is missing the family declaration.

**FINDING-007 — Page is 9476px tall; some sticky panels over-breathe.**
The "Make loyal members" section has a giant empty top — when scrollIntoView hits the section, you see ~600px of black before the eyebrow + headline appear. Each scroll-pinned section is reasonable on its own; collectively they make a 7-viewport scroll. Gym owners who landed from your cold email will not scroll 7 viewports.
**Fix:** audit per-section `minHeight: 100vh` declarations and shave the ones that don't need full-viewport pinning. The first scroll-into-view of each sticky section should land with the headline already mostly visible, not at the top of empty space. Scope: medium — needs viewport math per section, not a one-line tweak.

**FINDING-008 — Mobile nav touch targets are 17px tall.**
Browse measurement: "How it works", "Why it matters", "Pricing", "FAQ" all return 17px height. Acceptable on desktop hover, fails mobile (44px minimum). I didn't fully verify whether the mobile breakpoint switches to a hamburger — `BP.phone = 767`, so anything ≤767 should show a different nav. Worth a 60-second mobile-emulation pass.
**Fix:** if there's a mobile hamburger, this is moot — verify and close. If the desktop nav persists on mobile, add min-height 44px and adequate hit-area padding to nav links.

### Polish

**FINDING-009 — "Reward Examples" hierarchy feels weaker than siblings.**
Section eyebrow ("Reward Benefit") + 36px H3 ("Reward Examples") is smaller than the other section H2s (48-80px). Reads as a sub-section to "Make loyal members" but it's doing the work of its own narrative beat. Consider promoting to H2 with matching scale, or accepting the demotion as intentional and visually tying it tighter to the loyalty section above.

**FINDING-010 — Loyalty timeline's middle circle visually different from siblings.**
"+160 PTS" sits in an empty dark circle between two photo-filled circles. Reads as a missing image, not as a deliberate stat treatment. Either give it a distinct treatment (e.g., a glow ring, an orange fill, larger numerals) so it's clearly the "stat" beat, or replace with a stylized icon at the same visual weight as the photo siblings.

**FINDING-011 — Hero arcs feel tentative.**
The orbital arc lines are a nice atmospheric choice but at desktop they're ~1px thin and barely rotate before you scroll past them. Either lean in (thicker, more confident, slightly more contrast against the ink) or pull back further (more subtle, more decorative). Right now they're in the uncanny middle.

**FINDING-012 — Extend `text-wrap: balance` to the bottom CTA.**
Footer CTA "See it live. Book a 15-min demo." renders as 72px stacked. `headlineLine1` and `headlineLine2` are split into two strings (`COPY.footer`). Should be one h2 with `\n` (project convention permits this — `whiteSpace: pre-line` is set globally per `CLAUDE.md`) plus `text-wrap: balance` so it lays out as a single composed unit at every breakpoint.

**FINDING-013 — Font weight over-declaration.**
Inter 300/500 declared but never loaded. Removing them shrinks the `<link rel="preload">` list (or the font-face block). Tiny win, but the kind of thing that signals taste.

---

## Recommended fix order

One commit per fix:

1. **FINDING-002** (zero-stat bug) — render final values, remove scroll-driven count. Highest user-facing risk, smallest change. ~2 lines.
2. **FINDING-001** (above-the-fold) — tighten `heroMinH` and `heroPad` so headline + CTA fit at 1280×720. Verify at 1440×900, 1280×720, 768×1024, 390×844. ~1 minute, screenshot diff to confirm.
3. **FINDING-005 + FINDING-006** (default blue anchors + serif leak) — same root cause, fix together. ~30 seconds.
4. **FINDING-008** (mobile nav touch targets) — verify mobile hamburger exists; if not, add tap-area padding. ~5 minutes.
5. **FINDING-004** (reduced-motion) — add `useReducedMotion` hook, gate the orbital arcs, the why-it-matters animation (now removed by #2 anyway), and the auto-advancing loop. ~15 minutes.
6. **FINDING-007** (page height / over-breathing sections) — viewport math per sticky section. ~30 minutes; needs judgment per section.
7. **FINDING-010** (loyalty middle circle) — design choice; could be a 5-minute color tweak or a 30-minute redesign.
8. **FINDING-009 / 011 / 012 / 013** — polish, low-priority.

**Out of /design-review scope (decide separately):**

- **FINDING-003 (Babel in browser)** — needs a real build step (Vite/esbuild), changes the deploy story. Not a CSS/JSX fix. Worth tackling before the next batch of cold outreach but should be its own focused session.

---

## Critical files

- `hifi/landing.jsx:218-219` — desktop hero sizing tokens
- `hifi/landing.jsx:983-1078` — Hero component
- `hifi/landing.jsx:2849-2967` — WhyItMatters component (the zero-stat bug)
- `hifi/landing.jsx:702-895` — Nav component (touch-target review)
- `hifi/landing.jsx:906-981` — HeroOrbitalArcs (motion-prefs gating)
- `hifi/landing.jsx:1233-1488` — HowItWorks (sticky pin viewport math)
- `hifi/landing.jsx:2324-2381` — Loyalty section (middle-circle treatment)
- `hifi/landing.jsx:2983-3206` — Footer (bottom CTA `text-wrap: balance`)

The COPY dict at `landing.jsx:27-179` is well-structured (matches the strict no-hardcoded-strings rule from `CLAUDE.md`). All copy edits go there, not in JSX.

---

## Headline scores

- **Design Score: B** — solid fundamentals, real brand, real copy. One real bug (the zero-stat), one real perf concern (Babel-in-browser), and a hero that wastes its prime real estate. Nothing about this looks AI-generated; it looks like a careful first build that hasn't yet been polished by user testing.
- **AI Slop Score: A−** — almost none of the 11 blacklist patterns hit. No purple gradient, no 3-column icon-in-circle grid, no centered-everything, no decorative blobs, no generic "Welcome to..." copy. The page has a point of view. Rare and good.

---

## Verification

After fixes, re-run /design-review (with the dev server still up) and compare:

1. Above-the-fold check: at 1280×720, headline reads to completion AND orange CTA is visible. Repeat at 1440×900, 768×1024, 390×844.
2. WhyItMatters: hard-reload the page, immediately anchor-jump to `/#why`. Numbers should read "7×" and "$9k" — never "0×" / "$0k".
3. Default-blue scan: `$B js "[...document.querySelectorAll('a')].filter(a=>getComputedStyle(a).color==='rgb(0, 0, 238)').length"` should return 0.
4. Reduced-motion: macOS System Settings → Accessibility → Display → Reduce motion ON, hard-reload. Orbital arcs should be static; counters (if kept) should not animate.
5. Mobile nav: emulate 390×844, tap each nav link target — every target ≥44px on the long axis.
6. Total page height: should drop below 9000px after sticky-section over-breathing is fixed.
