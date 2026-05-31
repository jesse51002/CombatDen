---
name: CombatDen LandingPage
description: Light, product-grade marketing site that sells the retention layer and the design thesis to class-based gym owners.
colors:
  bg: "#f3f5f8"
  bg-alt: "#eef1f6"
  surface: "#ffffff"
  ink: "#16181d"
  ink-soft: "#565b66"
  ink-faint: "#878d99"
  line: "rgba(20,22,30,0.09)"
  line-soft: "rgba(20,22,30,0.06)"
  accent: "#2A67BD"
  accent-dark: "#1F5099"
  accent-soft: "#E8F0FB"
  accent-glow: "rgba(42,103,189,0.18)"
  cyan-glow: "oklch(0.72 0.15 215 / 0.13)"
typography:
  hero:
    fontFamily: "'Geist', sans-serif"
    fontSize: "clamp(40px, 6vw, 68px)"
    fontWeight: 600
    lineHeight: 1.0
    letterSpacing: "-2.4px"
  title:
    fontFamily: "'Geist', sans-serif"
    fontSize: "clamp(30px, 3.4vw, 44px)"
    fontWeight: 600
    lineHeight: 1.08
    letterSpacing: "-1.5px"
  statement:
    fontFamily: "'Geist', sans-serif"
    fontSize: "clamp(28px, 3.6vw, 46px)"
    fontWeight: 550
    lineHeight: 1.18
    letterSpacing: "-1.4px"
  numeral:
    fontFamily: "'Geist', sans-serif"
    fontSize: "clamp(52px, 8vw, 104px)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-4px"
  body:
    fontFamily: "'Geist', sans-serif"
    fontSize: "clamp(16px, 1.8vw, 20px)"
    fontWeight: 450
    lineHeight: 1.5
    letterSpacing: "normal"
  label:
    fontFamily: "'Geist Mono', ui-monospace, monospace"
    fontSize: "9–12px"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "0.4–0.6px"
    textTransform: "uppercase"
rounded:
  button: "12px"
  input: "12px"
  card: "22px"
  card-large: "28px"
  panel: "26px"
  pill: "999px"
spacing:
  hairline: "8px"
  tight: "16px"
  base: "24px"
  loose: "48px"
  section: "100–130px"
components:
  button-primary:
    background: "linear-gradient(180deg, {colors.accent}, {colors.accent-dark})"
    textColor: "#ffffff"
    rounded: "{rounded.button}"
    padding: "13px 22px"
    shadow: "0 1px 2px rgba(15,45,95,0.32), 0 8px 22px -6px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)"
  button-secondary:
    background: "{colors.surface}"
    textColor: "{colors.ink}"
    border: "1px solid {colors.line}"
    rounded: "{rounded.button}"
    shadow: "0 1px 2px rgba(20,22,40,0.05)"
  card-soft:
    background: "linear-gradient(180deg, #ffffff, #f5f7fb)"
    border: "1px solid rgba(20,22,40,0.065)"
    rounded: "{rounded.card}"
    shadow: "0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2), inset 0 1px 0 rgba(255,255,255,0.9)"
  panel-frosted:
    background: "linear-gradient(180deg, rgba(255,255,255,0.6), rgba(246,248,252,0.42))"
    backdropFilter: "blur(20px) saturate(150%)"
    rounded: "{rounded.panel}"
    shadow: "0 0 0 1px rgba(20,22,40,0.05), 0 50px 90px -52px rgba(20,22,50,0.3), inset 0 1px 0 rgba(255,255,255,0.7)"
  nav:
    background-scrolled: "rgba(243,245,248,0.78)"
    backdropFilter-scrolled: "saturate(180%) blur(14px)"
    height: "68px"
  input:
    background: "#ffffff"
    border: "1px solid {colors.line}"
    border-focus: "1px solid {colors.accent}"
    ring-focus: "0 0 0 3px rgba(42,103,189,0.13)"
    rounded: "{rounded.input}"
---

# Design System: CombatDen LandingPage

## 1. Overview

**Creative North Star: "Product-grade calm."**

The page should read like a beautifully built product, not a marketing brochure. Light, airy, and
precise (Raycast / Linear lineage): a cool off-white ground, one confident blue, Geist's clean
geometry, soft layered shadows, and real device mockups that look like the actual app. The whole
page is itself the proof of the design thesis. If a prospect isn't impressed by how it looks, the
design bet has failed at the first gate.

The system is **calm, premium, and concrete**. It rejects what PRODUCT.md names as anti-references:
generic gym SaaS (mint/teal lifestyle pages), AI-slop (purple gradients, icon-grid templates, blob
graphics), and replacement-CRM positioning. The work that carries identity is the **soft-glass card
surfaces, the single blue accent + its vertical gradient, and the live theme-able app mockups** that
re-skin to a gym's brand.

> This is a full redesign. It replaces the prior dark "Fight Card" system (warm-near-black ground,
> Jura display, orange accent, flat-no-shadow). The named rules below **invert** several of that
> system's rules on purpose (shadows and frosted glass are now part of the language; the accent is
> blue and gradient-bearing; the ground is light). Do not reintroduce the old rules.

**Key Characteristics:**
- One blue accent, carried by a subtle vertical gradient on primary actions.
- Light, tinted ground (`#f3f5f8`), white surfaces that lift off it with soft shadow.
- Geist everywhere readable; Geist Mono for small tracked labels and captions.
- Soft, layered, diffuse shadows convey lift. Used deliberately, never harsh.
- Frosted glass (backdrop-blur) on the nav, the pricing panel, and the in-app notification, purposefully.
- Atmosphere from radial accent glows and faint dot-grids behind hero / pricing / recs / loyalty / why.

## 2. Colors

A light, cool-neutral stage with one blue accent and its darker gradient partner. Tinted neutrals,
one accent family. The per-gym **theme accent** (theme-store.jsx) overrides the blue *inside the
mocks* so the app can wear any brand.

### Accent
- **Accent** (`#2A67BD`): the single brand blue. Primary CTAs, links, active states, stat numerals,
  agent marks, mock accents. Primary buttons use a vertical gradient `accent → accent-dark`.
- **Accent Dark** (`#1F5099`): gradient partner and the color for emphasized numerals (prices, stats).
- **Accent Soft** (`#E8F0FB`): faint accent wash for chips, check pills, active rows, icon wells.
- **Accent Glow** (`rgba(42,103,189,0.18)`) and **Cyan Glow** (`oklch(0.72 0.15 215 / 0.13)`):
  radial-gradient atmosphere blobs behind sections.

### Neutral
- **BG** (`#f3f5f8`) / **BG Alt** (`#eef1f6`): the page ground and a slightly cooler step for inset
  rows and chips. Cool off-white, never a flat gray.
- **Surface** (`#ffffff`): cards, the nav-at-rest content, inputs. White surfaces lift off the
  tinted ground via shadow + a soft top-to-bottom gradient (`#ffffff → #f5f7fb`).
- **Ink** (`#16181d`) / **Ink Soft** (`#565b66`) / **Ink Faint** (`#878d99`): the three-step text
  ramp. Headlines and primary text in ink; descriptions in ink-soft; captions, mono labels, and
  small print in ink-faint.
- **Line** (`rgba(20,22,30,0.09)`) / **Line Soft** (`rgba(20,22,30,0.06)`): hairline borders and
  table row rules.

### Named Rules

**The One-Accent Rule.** The site has one blue. Tints (`accent-soft`), the gradient partner
(`accent-dark`), and the glows are all derived from it. Do not introduce a second brand color.
The exception is the **mock surfaces**, which take a gym's theme accent so the app reads as theirs.

**The Gradient-On-Actions Rule.** Primary buttons, featured pricing CTA, agent marks, and the small
brand pills carry the `accent → accent-dark` vertical gradient. Flat-blue fills look unfinished next
to them. Gradient is for actions and brand marks, never for text (no gradient text).

**The Tinted-Neutral Rule.** The ground is `#f3f5f8`, not `#fff`; surfaces are `#fff` lifted by
shadow. Don't flatten the page to a single white; the tinted ground is what lets white cards read as
elevated.

## 3. Typography

**Sans:** Geist (with Inter, system-ui fallback) — clean, slightly geometric, product-grade. Carries
every readable word and every headline.
**Mono:** Geist Mono — small uppercase tracked labels, eyebrows, captions, prices' "PTS"/cadence,
timestamps. The mono is the texture signal that this is a built product.

**Character:** A one-family-plus-mono system. Geist does display and body (weight + size carry
hierarchy); Geist Mono does the small technical labels. Headlines run tight (negative letter-spacing
down to about −2.4px at hero scale) — the tightening is part of the look.

### Hierarchy

- **Hero** (Geist 600, clamp(40–68px), line-height 1.0, tracking −2.4px): the single H1.
- **Title** (Geist 600, clamp(30–44px), tracking −1.5px): section H2s.
- **Statement** (Geist 550, clamp(28–46px), tracking −1.4px): the §2 two-tone one-liner.
- **Numeral** (Geist 700, clamp(52–104px), tracking −4px, tabular): ROI stats and prices, in
  `accent-dark`.
- **Body** (Geist 450, clamp(16–20px), line-height 1.5): sublines and descriptions. Cap at 65–75ch.
- **Label** (Geist Mono 500, 9–12px, tracked 0.4–0.6px, UPPERCASE): eyebrows, captions, chips,
  "Owner view", timestamps, "PTS".

### Named Rules

**The Numerals-Are-Geist-Bold Rule.** Prices, points, and ROI stats are Geist 700 with tabular
figures in `accent-dark`, animated with a count-up where they anchor a section.

**The Mono-For-Furniture Rule.** Small technical labels (eyebrows, captions, timestamps, status
text) are Geist Mono, uppercase, tracked. Body copy is never mono.

**The No-Gradient-Text Rule.** `background-clip: text` with a gradient is forbidden. Emphasis comes
from weight, size, color (ink ramp), and the two-tone accent period in §2.

**The No-Em-Dash Rule.** No em dashes in user-visible copy (PRODUCT.md principle). Commas, periods,
or two sentences.

## 4. Elevation

The system is **soft-shadow + frosted-glass**, Raycast-lineage. Lift is real (diffuse layered
shadows), not faked with borders. Glass (backdrop-blur) is used on exactly the surfaces that should
feel like they float over content.

- **Soft card shadow:** `0 1px 2px rgba(20,22,40,0.03), 0 22px 50px -30px rgba(20,22,50,0.2),
  inset 0 1px 0 rgba(255,255,255,0.9)`. Layered: a tight contact shadow, a wide soft drop, and a top
  inset highlight. Never a single hard shadow.
- **Frosted glass:** nav-on-scroll, the pricing comparison panel, the in-app "30 min before" video
  notification. `backdrop-filter: blur + saturate` over a translucent white.
- **Glows + dot-grids:** radial accent/cyan glows and faint masked dot-grids sit behind the hero,
  pricing, recs, loyalty, and why sections as atmosphere (z-index 0, pointer-events none).

### Named Rules

**The Layered-Shadow Rule.** Shadows are multi-stop and diffuse (contact + soft drop + inset
highlight). A single `0 4px 8px` shadow reads as 2014 Material; rebuild it layered.

**The Purposeful-Glass Rule.** Frosted glass appears on the nav, the pricing panel, and the floating
notification, surfaces that genuinely overlay content. Do not glass every card; default card
surfaces are the soft white gradient, not glass.

## 5. Components

### Buttons (`chrome.jsx` `GWButton`)
- **Shape:** rounded rectangle, radius 12. (This system is not pill-buttoned; pills are reserved for
  chips, badges, and dots.)
- **Primary:** `accent → accent-dark` vertical gradient, white label, layered glow shadow, optional
  arrow glyph. Sizes sm/md/lg via padding + font-size.
- **Secondary:** white surface, ink label, 1px line border, soft shadow.

### Cards (`feed.jsx`, `loyalty.jsx`)
- Soft white gradient (`#ffffff → #f5f7fb`), 1px low-contrast border, layered soft shadow, inset top
  highlight. Radius 22 (cells) / 28 (the big feature card). Never a flat harsh white box.

### Pricing panel (`pricing-table.jsx`)
- One frosted-glass comparison panel (radius 26). The featured column ("Customization") is raised
  with an accent top-edge, a faint accent gradient tint, and a "Most popular" mono badge.

### Navigation (`chrome.jsx` `GWNav`)
- Sticky, transparent at rest; on scroll it becomes a frosted bar (`rgba(243,245,248,0.78)` +
  backdrop blur) with a hairline bottom border. 68px tall. Brand mark + wordmark left (from `BRAND`),
  links center, demo CTA right.

### Inputs (`footer.jsx`)
- White surface, 1px line border, radius 12. Focus: accent border + a 3px soft accent ring. One
  accent; no separate error red beyond the small system red used for the submit-failure line.

### Phone mock (`mocks/phone-mock.jsx`) — theme-driven
- Device frame (soft metal gradient bezel, dynamic island) around `GymAppScreen`. The screen reads
  the **global active theme**: its accent re-tints the UI and its image (from `THEME_ASSETS`) fills
  the hero video tile. A theme change re-skins every single-device mock at once.

### Theme preview (`mocks/theme-preview.jsx`) — prop-driven
- A flat app-screen card in a *given* brand theme. Prop-driven so the §3 rail can show many brands
  side by side. Clickable: selecting one sets the global theme.

### Stat numeral (`why.jsx`)
- Large Geist 700 tabular numeral in `accent-dark`, count-up on scroll-into-view, with a body line
  below and an optional mono math annotation.

## 6. Do's and Don'ts

### Do:
- **Do** use one blue (`#2A67BD`) and its gradient partner (`#1F5099`) / soft tint (`#E8F0FB`).
- **Do** put the `accent → accent-dark` gradient on primary actions and brand marks.
- **Do** use `#f3f5f8` ground with white (`#ffffff`) cards lifted by soft layered shadow.
- **Do** set Geist for everything readable, Geist Mono for small tracked uppercase labels.
- **Do** set prices/points/stats in Geist 700 tabular, in `accent-dark`.
- **Do** convey lift with layered diffuse shadows (contact + soft drop + inset highlight).
- **Do** reserve frosted glass for the nav, pricing panel, and floating notification.
- **Do** drive the mock imagery + accent from the global theme store; let the §3 rail show many brands.
- **Do** cap body line length at 65–75ch and keep tap targets ≥44px on mobile.

### Don't:
- **Don't** reintroduce the old dark system (warm-near-black ground, Jura, orange, flat-no-shadow).
- **Don't** use mint/teal "wellness" green, or purple/indigo AI-slop gradients.
- **Don't** apply `background-clip: text` with a gradient. Emphasis is weight/size/color.
- **Don't** use a single hard `box-shadow`; shadows are layered and diffuse.
- **Don't** glass every surface; default cards are the soft white gradient, glass is purposeful.
- **Don't** use em dashes in user-visible copy.
- **Don't** use `border-left`/`border-right` > 1px as a colored side-stripe on cards or callouts.
- **Don't** imply "switch to us" / "replace your CRM"; we run alongside (PRODUCT.md anti-reference).
- **Don't** ship motion that ignores `prefers-reduced-motion` (the count-up in `why.jsx`, the
  auto-loops in `recs.jsx` / `loyalty.jsx`, and the nav blur do not yet honor it — known gap).
