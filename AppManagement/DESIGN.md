---
name: AppManagement
description: Gym admin web app — a calm, premium, daylit control desk for the member-retention engine.
colors:
  paper: "#F6F3EE"
  ink: "#27231E"
  sapphire: "#2A67BD"
  deep-sapphire: "#274777"
  status-good: "#1D7D3E"
  status-warn: "#915C08"
  status-bad: "#B6322D"
  link: "#0E5CAF"
typography:
  display:
    fontFamily: "Hanken Grotesk, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    letterSpacing: "0"
  headline:
    fontFamily: "Hanken Grotesk, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Hanken Grotesk, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  label:
    fontFamily: "Hanken Grotesk, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "Hanken Grotesk, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    letterSpacing: "0.03em"
rounded:
  sm: "8px"
  md: "12px"
spacing:
  tiny: "2px"
  small: "4px"
  medium: "8px"
  large: "16px"
  big: "32px"
components:
  button-primary:
    backgroundColor: "{colors.sapphire}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    padding: "8px 16px"
  button-outline:
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "8px 16px"
  object-card:
    backgroundColor: "{colors.ink}"
    rounded: "{rounded.md}"
---

# Design System: AppManagement

## 1. Overview

**Creative North Star: "The Daylit Control Desk"**

A calm, well-lit front desk you trust at a glance. Warm paper, near-black ink, and a single
sapphire accent that marks the one thing needing attention. The surface is quiet and
premium; structure comes from whitespace, thin hairline rules, and type hierarchy, not from
boxing every section in a card. The owner glances between classes and reads the retention
engine (attendance, ranks, points, rewards, redemptions) in seconds.

It is **vertical-neutral** by mandate: it must feel as right behind a pilates studio as a BJJ
gym, so it carries no combat-sports coding (no fists, cages, aggressive type) and no
wellness-spa cliche. Because these screens double as a sales artifact, polish is load-bearing
on every surface, including ones no one would screenshot.

It explicitly rejects the incumbent gym CRMs (Mindbody, PushPress, Zen Planner), spreadsheet
density, and the generic Bootstrap-y SaaS dashboard. If a viewer could say "a template made
that," the screen has failed.

**Key Characteristics:**
- Warm paper background, warm-ink text; never pure white or black.
- One sapphire accent, used sparingly and meaningfully.
- A single humanist sans (Hanken Grotesk) with tabular figures; hierarchy from weight + scale.
- De-carded: sections live on the page, separated by hairlines; cards are reserved for
  discrete, repeated objects (reward / redemption / class cards).
- Tight 12 / 8px corners. Calm, confident, credible.

## 2. Colors

A warm near-monochrome paper field with one sapphire voice and a small, deliberately darkened
set of semantic status hues that read on light.

### Primary
- **Sapphire** (`#2A67BD`): the single accent. Active nav, primary action, focus rings,
  progress arcs, chart series, the one figure that matters. As a fill it carries a paper
  label; as text/icons on paper it reads at 5:1.

### Secondary
- **Deep Sapphire** (`#274777`): the darker companion (the donut "inactive" arc, the Material
  `secondary` slot). Quiet, recedes behind the primary.

### Tertiary — Semantic Status (functional, darkened for paper)
- **Good** (`#1D7D3E`): on-track / checked-in / streak alive.
- **Warn** (`#915C08`): at-risk / slipping (amber, not yellow, so it reads on paper).
- **Bad** (`#B6322D`): churn-risk / error.
- **Link** (`#0E5CAF`): hyperlinks (email, etc.).

### Neutral
- **Paper** (`#F6F3EE`): the surface. Warm off-white, never `#fff`. Also doubles as the
  knockout label color on sapphire fills.
- **Ink** (`#27231E`): primary text. Warm near-black, never `#000`. `text2nd` / `text3rd` are
  ink at 75% / 50% for secondary and muted copy.
- **Panel** (ink @ 10%): the only "surface" tint, used as the background of discrete object
  cards, the sidebar rail, and small controls (search box, pills). Hairlines/dividers use this
  same low-contrast tint.

### Named Rules
**The One Light Rule.** Sapphire appears on ≤10% of any screen; it marks the single most
important thing. Status hues are functional and exempt but stay muted so they never read as a
second accent.

**The Tinted Neutral Rule.** No pure black, no pure white. Paper and ink are both warm-tinted.

## 3. Typography

**Display / Body Font:** Hanken Grotesk (humanist sans), with `sans-serif` fallback.
**Numerals:** tabular figures everywhere, so columns and metrics align.

**Character:** one warm humanist sans does all the work, crafted and approachable rather than
the cold geometric grotesque of generic SaaS.

### Hierarchy
- **Display** (`big2`, 600, 32px): the one big figure or the member name. Used sparingly.
- **Headline** (`h1`, 700, 24px, -0.02em): page titles, member name.
- **Title** (`h2`, 600, 16px): section titles, card titles.
- **Label** (`h3`, 600, 13px): table headers, chips, metadata.
- **Body** (`p`, 400, 12px, 0.03em): default reading text; cap measured text at 65–75ch.

### Named Rules
**The Weight-Not-Family Rule.** Hierarchy comes from weight and scale within Hanken Grotesk,
never from switching typefaces. Keep ≥1.25 scale steps; flat scales read as a spreadsheet.

## 4. Elevation

Flat. Depth comes from **whitespace, hairline rules, and tonal panels**, not drop shadows.
Page sections sit directly on the paper, separated by 32px rhythm and 1px `Hairline` rules
(horizontal between stacked sections, vertical between side-by-side panes). The only raised
surface is a discrete object card (ink @ 10% panel, 12px corners); even those are flat at
rest. Shadows are reserved for genuinely transient surfaces (menus, dialogs).

### Named Rules
**The De-Card Rule.** Do not box a page section in a card. Cards are only for discrete,
repeated *objects* (a reward, a redemption, a class). Sections are structured by space +
hairlines + titles. Nested cards are always wrong.

## 5. Components

### Buttons
- **Shape:** 12px corners (`radiusBig`).
- **Primary:** sapphire fill, **paper** label (knockout), used for the one main action.
- **Outline:** 2px ink border, ink label, transparent fill, for secondary actions (Print,
  Edit, Promote, View all).

### Hairline
- A 1px rule in the panel tint. Horizontal separates stacked sections; `vertical: true`
  separates side-by-side columns (dashboard panes, KPI stats, the member rail).

### Object Cards (reward / redemption / class)
- Panel background (ink @ 10%), 12px corners, image hero on top with a sapphire **price pill**
  (top-right), then centered title, points in sapphire, and a status/action footer
  ("Review & confirm" when pending, a green "Approved" when done). Laid out in a `FillGrid`
  that caps columns at item count so a short row fills the width.

### Pills / Chips
- Small rounded (`radiusSmall`) tints: the sapphire price pill (paper label), the muted
  sapphire KPI delta chip, the filter pills (sapphire fill + paper label when selected).

### Tables
- `AppDataTable` only (header row + hairline-separated rows). Status values are colored text
  (good/warn/bad), never filled cells. Numerals are tabular.

### Navigation
- Left rail (panel tint), the Apex MMA mark on top, then icon + label items. Active item is
  ink; the primary "Add New Member" CTA is sapphire.

## 6. Do's and Don'ts

### Do:
- **Do** keep sapphire to ≤10% of a screen; let it mark the single most important thing.
- **Do** separate sections with whitespace + hairlines + titles, not cards (the De-Card Rule).
- **Do** reserve cards for discrete repeated objects (reward / redemption / class cards).
- **Do** tint every neutral; paper not `#fff`, ink not `#000`.
- **Do** build hierarchy from weight + scale in Hanken Grotesk; use tabular figures for data.
- **Do** put a **paper** label on sapphire fills, and use **sapphire** for accent text on paper.
- **Do** hold text + meaningful UI to WCAG AA; respect `prefers-reduced-motion`.

### Don't:
- **Don't** look like the incumbent gym CRMs (Mindbody, PushPress, Zen Planner), dense, dated
  operational clutter.
- **Don't** produce spreadsheet density, walls of uniform-weight data with no hierarchy.
- **Don't** fall into generic SaaS admin, grey cards, blue hyperlinks, default-everything,
  the hero-metric-with-gradient cliche.
- **Don't** use combat-sports machismo, fight imagery, cages, aggressive condensed type.
- **Don't** box page sections in cards or nest cards. Don't add a second accent.
- **Don't** use side-stripe borders, gradient text, or decorative glassmorphism.
