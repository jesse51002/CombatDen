---
name: CRM
description: Gym admin web app — a calm, premium, daylit control desk for the member-retention engine.
colors:
  ground: "#F3F5F8"
  surface: "#FFFFFF"
  ink: "#16181D"
  sapphire: "#2A67BD"
  accent-dark: "#1F5099"
  deep-sapphire: "#274777"
  status-good: "#1D7D3E"
  status-warn: "#915C08"
  status-bad: "#B6322D"
  link: "#1F5099"
typography:
  display:
    fontFamily: "Geist, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Geist, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Geist, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "-0.0125em"
  label:
    fontFamily: "Geist, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "Geist, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    letterSpacing: "0.03em"
rounded:
  sm: "8px"
  md: "12px"
  card: "20px"
spacing:
  tiny: "2px"
  small: "4px"
  medium: "8px"
  large: "16px"
  big: "32px"
components:
  button-primary:
    background: "linear-gradient({colors.sapphire} -> {colors.accent-dark})"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
    padding: "8px 16px"
  button-outline:
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "8px 16px"
  object-card:
    backgroundColor: "{colors.surface}"
    border: "1px hairline (ink @ 9%)"
    shadow: "soft layered (cardShadow)"
    rounded: "{rounded.card}"
---

# Design System: CRM

## 1. Overview

**Creative North Star: "The Daylit Control Desk"**

A calm, well-lit front desk you trust at a glance. A cool, bright off-white ground, white
lifted surfaces, near-black ink, and a single sapphire accent that marks the one thing
needing attention. The surface is quiet and premium; structure comes from whitespace, thin
hairline rules, and type hierarchy, not from boxing every section in a card. The owner
glances between classes and reads the retention engine (attendance, ranks, points, rewards,
redemptions) in seconds.

It is **landing-aligned**: it shares the marketing landing page's design system
(`../LandingPage/hifi/ds.jsx` — cool ground, white cards, sapphire + gradient, Geist) so the
public theme browser (`themes.combatden.net`, a second build target of this app) reads as a
direct extension of the marketing site rather than a separate admin tool.

It is **vertical-neutral** by mandate: it must feel as right behind a pilates studio as a BJJ
gym, so it carries no combat-sports coding (no fists, cages, aggressive type) and no
wellness-spa cliche. Because these screens double as a sales artifact, polish is load-bearing
on every surface, including ones no one would screenshot.

It explicitly rejects the incumbent gym CRMs (Mindbody, PushPress, Zen Planner), spreadsheet
density, and the generic Bootstrap-y SaaS dashboard. If a viewer could say "a template made
that," the screen has failed.

**Key Characteristics:**
- Cool off-white ground (`#F3F5F8`), white lifted surfaces, a cool near-black ink ramp.
- One sapphire accent (with a gradient partner for primary actions), used sparingly.
- Geist (the landing page's typeface) with tabular figures; hierarchy from weight + scale.
- De-carded sections: sections live on the page, separated by hairlines. Discrete, repeated
  objects (reward / redemption / class / theme cards) are white cards that lift on a soft,
  layered shadow.
- Tight 12 / 8px corners (20px on object cards). Calm, confident, credible.

## 2. Colors

A cool near-monochrome field with one sapphire voice (plus its gradient partner) and a small,
deliberately darkened set of semantic status hues that read on light.

### Primary
- **Sapphire** (`#2A67BD`): the single accent. Active nav, primary action, focus rings,
  progress arcs, chart series, the one figure that matters. As text/icons on the ground it
  reads at AA; as a fill it carries a white label.
- **Accent Dark** (`#1F5099`): the gradient partner. Primary actions are a top→bottom
  `sapphire → accent-dark` gradient (`primaryGradient`) with a soft blue shadow; also the
  hyperlink color.

### Secondary
- **Deep Sapphire** (`#274777`): the darker companion (the donut "inactive" arc, the Material
  `secondary` slot). Quiet, recedes behind the primary.

### Tertiary — Semantic Status (functional, darkened for the light ground)
- **Good** (`#1D7D3E`): on-track / checked-in / streak alive.
- **Warn** (`#915C08`): at-risk / slipping (amber, not yellow, so it reads on light).
- **Bad** (`#B6322D`): churn-risk / error.
- **Link** (`#1F5099`): hyperlinks (email, etc.) — the accent-dark.

### Neutral
- **Ground** (`#F3F5F8`): the page field. Cool off-white, never `#fff`. The scaffold sits on
  it; cards lift off it.
- **Surface** (`#FFFFFF`): white card surface. Discrete object cards and small controls
  (search box, pills) are white, lifted off the ground by a hairline border + soft shadow.
- **Ink** (`#16181D`): primary text. Cool near-black, never `#000`. `text2nd` (`#565B66`) /
  `text3rd` (`#878D99`) are the fixed cool-ink ramp for secondary and muted copy (no longer
  alpha-derived).
- **Line** (ink @ 9%): the hairline. Used for dividers and card/control borders — decoupled
  from the card fill (a white card needs a visible border).

### Named Rules
**The One Light Rule.** Sapphire appears on ≤10% of any screen; it marks the single most
important thing. Status hues are functional and exempt but stay muted so they never read as a
second accent.

**The Cool-Tinted Rule.** No pure black. The ground and ink are cool-tinted (`#F3F5F8` /
`#16181D`), never warm and never `#000`. Cards are pure white (`#FFFFFF`) so they lift cleanly
off the cool ground.

### Dark theme — the night shift

The CRM ships **light + dark + system** (per-employee, persisted in
`gym_employees.theme_preference`; chosen in **Settings → Appearance**). Dark is the *same
Restrained system inverted onto night*, not a separate look — it keeps the single sapphire
voice and the One Light / Cool-Tinted rules. It is a cool **charcoal**, deliberately **not navy**
(that would be the gym-admin-dark reflex). Implementation: every color/type/shadow token in
`design_constants.dart` is a getter that resolves through `themeController.isDark`.

The inversions that matter:
- **Surfaces lift by getting *lighter***, not by shadow (shadows barely read on dark). Ground
  `#14161B` (≈ the light theme's ink) → card `#1E212A` → popups `#242833`.
- **Ink ramp flips:** text `#E9ECF2` / `#A6ACB8` / `#828B98` (never `#fff`).
- **Hairlines flip light-on-dark** (cool-white @ ~12% / 7%).
- **Accent lightens** so it reads on dark: sapphire `#3E7CD6` (gradient deep stop `#2F62B5`,
  links `#5A93E6`); `onAccent` (the label on a sapphire fill) stays near-white in both themes.
- **Status hues brighten** (the light theme had darkened them to read on white): good `#3FB46A`,
  warn `#DBA13F`, bad `#E26C64`; the tinted status backgrounds become the hue @ ~18% over ground.

Both themes hold WCAG AA as the floor. The standalone **theme browser stays light-only** (a
marketing surface), and the member-app preview inside the phone frame is unaffected (it resolves
the tenant brand through `ShowcaseTokens`, not `DesignConstants`).

## 3. Typography

**Display / Body Font:** Geist (the landing page's typeface), with `sans-serif` fallback.
Loaded via `GoogleFonts.geist()`; `GoogleFonts.geistMono()` (`monoFont`) is available for
tracked micro-labels.
**Numerals:** tabular figures everywhere, so columns and metrics align.

**Character:** one clean, product-grade sans does all the work — the same typeface as the
marketing site, so admin and landing read as one product. Headings carry tight negative
tracking; body stays neutral.

### Hierarchy
- **Display** (`big2`, 600, 32px): the one big figure or the member name. Used sparingly.
- **Headline** (`h1`, 700, 24px, -0.02em): page titles, member name.
- **Title** (`h2`, 600, 16px): section titles, card titles.
- **Label** (`h3`, 600, 13px): table headers, chips, metadata.
- **Body** (`p`, 400, 12px, 0.03em): default reading text; cap measured text at 65–75ch.

**The kiosk ramp** (`kiosk*`, 19 roles, 112 → 11px): the member self-serve kiosk (a supervised
iPad) is read from ~2m, so it runs a **complete second ramp** with its own dedicated sizes
rather than borrowing the admin ramp for its smaller text — `kioskStreakNum` 112 ·
`kioskDisplay` 40 · `kioskMetric` 30 · `kioskPanelTitle` 25 · `kioskStatement` 22 ·
`kioskFieldText` 22 · `kioskTitle` 21 · `kioskButtonPrimaryLabel` 19 · `kioskName` 19 ·
`kioskSubtitle` 18 · `kioskButtonOutlineLabel` 17 · `kioskBody` 17 · `kioskLabel` 16 ·
`kioskSectionText` 16 · `kioskCaption` 15 · `kioskMicro` 13 · `kioskMonoValue` 13 ·
`kioskEyebrow` 12 · `kioskTag` 11. Kiosk-only — the admin surfaces never use these, and a
kiosk change never touches the admin ramp.

**The Kiosk-Moves-As-A-Set Rule.** Never re-scale one kiosk role alone. This ramp is
internally proportional, so lifting only *some* roles (the buttons, say) leaves labels at desk
scale and makes a button out-shout the copy beside it — a half-applied ramp is the same bug as
none. Change the ladder or nothing; a test asserts the ordering.

**Kiosk text holds the AA floor.** Muted words on a kiosk surface use `text2nd`, never
`text3rd` (3.05:1 on the ground, under the 4.5:1 AA floor and unreadable at 2m). `text3rd`
stays for non-text only — hairlines, progress tracks, placeholder glyphs.

### Named Rules
**The Weight-Not-Family Rule.** Hierarchy comes from weight and scale within Geist, never from
switching typefaces. Keep ≥1.25 scale steps; flat scales read as a spreadsheet.

## 4. Elevation

Page **sections** stay flat: they sit directly on the cool ground, separated by 32px rhythm
and 1px `Hairline` rules (horizontal between stacked sections, vertical between side-by-side
panes) — depth there comes from whitespace + hairlines, not boxes.

Discrete **object cards** (and the browser's top nav) do lift, with the landing page's soft,
layered shadow: white surface, a hairline border, and a diffuse `cardShadow` (a tight contact
shadow + a wide soft drop). Primary buttons carry a tighter blue `buttonShadow` under the
gradient. The browser's top bar is a frosted, translucent strip. Shadows are soft and diffuse,
never a single hard drop; transient surfaces (menus, dialogs) lift too.

### Named Rules
**The De-Card Rule.** Do not box a page *section* in a card. Cards are only for discrete,
repeated *objects* (a reward, a redemption, a class, a theme). Sections are structured by
space + hairlines + titles. Nested cards are always wrong.

**The Soft-Shadow Rule.** Elevation is always the soft, layered `cardShadow` / `buttonShadow`
(diffuse, low-contrast), never Material's default hard elevation or a single sharp drop.

## 5. Components

### Buttons
- **Shape:** 12px corners (`radiusBig`).
- **Primary** (`AppPrimaryButton`): the landing CTA — a `sapphire → accent-dark` gradient with
  a soft blue shadow and a **white** label, for the one main action. Pass `backgroundColor` to
  swap in a solid fill for a destructive/confirm action (that drops the gradient + shadow).
- **Outline** (`AppOutlineButton`): 2px ink border, ink label, transparent fill, for secondary
  actions (Print, Edit, Promote, View all).
- **Kiosk scale** (`KioskPrimaryButton` / `KioskOutlineButton`): the same two buttons one step
  larger — 19px label / 18x34 padding and 17px / 15x30 (`kioskButtonPrimaryLabel`,
  `kioskButtonOutlineLabel` and their padding tokens) — because the member kiosk is read and
  pressed from standing distance, the same reason the kiosk display type exists. These two
  wrappers are the only place those tokens are applied, so the whole kiosk button set scales
  together; the admin surfaces keep the base defaults.

### Hairline
- A 1px rule in the `line` tint (ink @ 9%). Horizontal separates stacked sections;
  `vertical: true` separates side-by-side columns (dashboard panes, KPI stats, the member
  rail).

### Object Cards (reward / redemption / class / theme)
- White surface (`surface`), 20px corners (`radiusCard`), a hairline border + soft `cardShadow`
  lift. Image hero on top with a sapphire **price/Active pill** (top-right), then centered
  title, points in sapphire, and a status/action footer ("Review & confirm" when pending, a
  green "Approved" when done). Laid out in a `FillGrid` that caps columns at item count so a
  short row fills the width.

### Pills / Chips
- Small rounded (`radiusSmall` / `radiusBig`) controls: the sapphire price/Active pill (white
  label), the muted sapphire KPI delta chip, the filter pills (white + hairline border when
  unselected, sapphire fill + white label when selected).

### Tables
- `AppDataTable` only (header row + hairline-separated rows). Status values are colored text
  (good/warn/bad), never filled cells. Numerals are tabular.

### Navigation
- **Admin:** left rail, the gym mark on top, then icon + label items. The active item is sapphire
  (icon + label) with a sapphire accent bar down its left edge; inactive items are gray
  (`text2nd`). The primary "Add New Member" CTA is also sapphire but carries **no** accent bar —
  that absent bar is what distinguishes the CTA from whichever section is active.
- **Theme browser:** the rail is replaced by a frosted, translucent **top bar** — a Flutter
  port of the landing nav (`ThemeBrowserTopBar`): CombatDen logo + wordmark on the left; Home /
  Pricing links + a gradient "Book a demo" CTA on the right — so the browser reads as one
  continuous site with the marketing page.

## 6. Do's and Don'ts

### Do:
- **Do** keep sapphire to ≤10% of a screen; let it mark the single most important thing.
- **Do** separate sections with whitespace + hairlines + titles, not cards (the De-Card Rule).
- **Do** reserve cards for discrete repeated objects (reward / redemption / class / theme); let
  them lift on the soft `cardShadow`, not Material's hard elevation (the Soft-Shadow Rule).
- **Do** keep the ground and ink cool-tinted (ground not `#fff`, ink not `#000`); cards are
  white that lifts off the ground.
- **Do** build hierarchy from weight + scale in Geist; use tabular figures for data.
- **Do** put a **white** label on sapphire/gradient fills, and use **sapphire** for accent text.
- **Do** hold text + meaningful UI to WCAG AA; respect `prefers-reduced-motion`.

### Don't:
- **Don't** look like the incumbent gym CRMs (Mindbody, PushPress, Zen Planner), dense, dated
  operational clutter.
- **Don't** produce spreadsheet density, walls of uniform-weight data with no hierarchy.
- **Don't** fall into generic SaaS admin, grey cards, blue hyperlinks, default-everything,
  the hero-metric-with-gradient cliche.
- **Don't** use combat-sports machismo, fight imagery, cages, aggressive condensed type.
- **Don't** box page sections in cards or nest cards. Don't add a second accent (the
  accent-dark is the gradient/link partner, not a separate voice).
- **Don't** use side-stripe borders or gradient **text** (gradient *fills* on the primary
  button are correct). The frosted top nav is the only blurred surface; don't scatter
  glassmorphism onto content.
