---
name: CombatDen
description: Member-retention layer for fighting gyms. Calm dark ledger, post-class spectacle.
colors:
  cage-orange: "#FF6C2D"
  ember-deep: "#692F16"
  canvas-black: "#121619"
  bone-text: "#F4F3EE"
  bone-soft: "#F4F3EEBF"
  bone-mute: "#F4F3EE80"
  surface-card: "#F4F3EE1A"
  link-blue: "#83C7FF"
  status-good: "#74F394"
  status-warn: "#CCCE44"
  status-bad: "#F94A4D"
typography:
  display-titanic:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "160px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0"
  display-hero:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "64px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0"
  display-medium:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "0"
  headline:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "0"
  title-soft:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "0.03em"
  subtitle:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0"
  body-large:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0"
  body:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.03em"
  caption:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "0.03em"
  eyebrow:
    fontFamily: "Jura, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0.24em"
rounded:
  sm: "16px"
  lg: "32px"
  pill: "1000px"
spacing:
  xs: "2px"
  sm: "4px"
  md: "8px"
  lg: "16px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.cage-orange}"
    textColor: "{colors.bone-text}"
    typography: "{typography.subtitle}"
    rounded: "{rounded.sm}"
    padding: "8px 16px"
  button-primary-disabled:
    backgroundColor: "#FF6C2D80"
    textColor: "{colors.bone-text}"
    rounded: "{rounded.sm}"
    padding: "8px 16px"
  button-outline:
    backgroundColor: "transparent"
    textColor: "{colors.bone-text}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    padding: "8px 16px"
  pill-timeframe-active:
    backgroundColor: "transparent"
    textColor: "{colors.bone-text}"
    typography: "{typography.title}"
    rounded: "{rounded.lg}"
    padding: "0 16px"
    height: "30px"
  pill-timeframe-rest:
    backgroundColor: "transparent"
    textColor: "{colors.bone-mute}"
    typography: "{typography.title}"
    rounded: "{rounded.lg}"
    padding: "0 16px"
    height: "30px"
  card-surface:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.bone-text}"
    rounded: "{rounded.lg}"
    padding: "16px"
  bottom-nav:
    backgroundColor: "{colors.canvas-black}"
    textColor: "{colors.bone-text}"
    height: "64px"
  sparkle-hero-accent:
    backgroundColor: "transparent"
    textColor: "{colors.cage-orange}"
    typography: "{typography.display-hero}"
    padding: "32px 16px"
---

# Design System: CombatDen

## 1. Overview

**Creative North Star: "The Loyalty Ledger"**

CombatDen is a points-and-streaks ledger that occasionally erupts into broadcast
celebration. Most surfaces are calm columns of progress: class lists, rank
deltas, points balances, video shelves. Then, exactly at the moments a member
earns something on the mat, the ledger goes loud — `SparkleHero` accent
numerals, all-caps eyebrows, scattered orange sparkles, the only place in the
system where the surface stops being quiet. Calm by default, kinetic when
attendance pays off.

The canvas is the gym after dark: near-black `#121619`, warm bone-white text,
sharp Material Symbols at light weight, Jura sans across every size. There is
no marketing aesthetic, no wellness softness, no consumer-fitness gamification.
The member is treated as a practitioner; the design treats their time the same
way. Density beats whitespace; legibility beats decoration; rationed
celebration beats constant cheerleading.

This system explicitly rejects the look-and-feel of generic fitness SaaS
(MyFitnessPal, Fitbod) — no pastel teal/lime accents, no cartoon mascots, no
"crush your goal" motivational chrome. It also rejects the gym-CRM-admin
density of Mindbody / ClassPass / Triib; CombatDen sits next to those tools
but is the member-facing layer, not another console.

**Key Characteristics:**
- Near-black canvas; cage-orange agency color used on ≤10% of any screen.
- Jura sans across the entire scale, from 11px caption to 160px display.
- No shadows. Depth comes from a 10%-bone tonal layer over the canvas.
- Rounded rectangles (16 / 32) for surfaces; full pills (1000) for outline buttons and tag selectors.
- Sharp Material Symbols, weight 300, T-shirt sized 16 / 20 / 24 / 28 / 32 / 36.
- Coach-to-athlete copy: imperative, factual, uppercase only on display eyebrows.
- Celebration is rationed to the post-class scaffold; everywhere else is quiet.

## 2. Colors: The Cage-and-Bone Palette

A two-color palette in spirit (a near-black canvas, a warm bone text) plus one
agency accent (cage orange) and a handful of semantic status colors. The brand
hue (orange) tints nothing else; neutrals stay genuinely neutral so the orange
keeps its weight.

### Primary

- **Cage Orange** (`#FF6C2D`): The agency color. Primary CTAs, the active
  metric accent, sparkle particles around post-class hero numerals. Used on
  primary-button fills, the focal numeral inside `SparkleHero`, and selected
  metric callouts. Never a background fill, never a gradient, never decoration.
- **Ember Deep** (`#692F16`): The deep ember below the orange. Used as a
  secondary brand surface (e.g., the home gym header treatment) where a
  warmer-than-canvas dark surface is needed without spending agency orange.

### Neutral

- **Canvas Black** (`#121619`): The default surface. Every screen, every
  scaffold. Tinted slightly toward the brand hue (it is *not* `#000`).
- **Bone Text** (`#F4F3EE`): Warm off-white. Body copy, headings, icons at
  rest, button text on primary and outline variants. Never `#fff`; the warmth
  is part of the system.
- **Bone Soft** (`#F4F3EE` at 75% / `#F4F3EEBF`): Secondary copy — meta lines,
  supporting labels, the inactive timeframe pill text-on-text-context.
- **Bone Mute** (`#F4F3EE` at 50% / `#F4F3EE80`): Tertiary metadata only —
  divider stripes, low-emphasis hints, the bottom-nav top border. Never used
  for actionable copy.
- **Surface Card** (`#F4F3EE` at 10% / `#F4F3EE1A`): The single tonal surface
  layer. Cards, popups, and any "raised" container are this 10% bone tint over
  Canvas Black. There is no second card layer above this.

### Semantic

- **Link Blue** (`#83C7FF`): Inline links only. Not a generic accent.
- **Status Good** (`#74F394`): Positive deltas, streak-on, success.
- **Status Warn** (`#CCCE44`): At-risk states, soft warnings.
- **Status Bad** (`#F94A4D`): Errors, broken streaks, destructive
  confirmations.

### Named Rules

**The One Voice Rule.** Cage Orange covers ≤10% of any screen. Its rarity is
the point. The instant orange becomes a background fill, a divider color, or a
chart axis, the agency signal collapses. If a screen needs warmth without
spending agency, use Ember Deep.

**The Single Tonal Layer Rule.** There is exactly one card surface
(`Surface Card`, 10% bone over canvas). Nested cards are forbidden. If
hierarchy is needed inside a card, use type weight, eyebrows, and dividers,
never a second tonal layer.

**The Tinted-Neutrals Rule.** Canvas Black is not `#000` and Bone Text is not
`#fff`. Both are tinted toward warm. Pure black or pure white inside a CombatDen
surface is a bug.

## 3. Typography

**Display Font:** Jura (with `system-ui, sans-serif` fallback)
**Body Font:** Jura
**Label / Eyebrow Font:** Jura

**Character:** A single-family system. Jura is geometric, technical, and
slightly mechanical — closer to a stopwatch face than to a brand wordmark. It
holds at 11px caption and 160px display without changing voice. The whole
system is pitched on one font's contrast, run hard.

### Hierarchy

- **Display Titanic** (Jura 700, 160px / 1.0): Reserved for ledger-style
  numerals — points totals on the points-store screen, single-screen number
  takeovers. Use rarely.
- **Display Hero** (Jura 700, 64px / 1.0): The `SparkleHero` accent line.
  Post-class only.
- **Display Medium** (Jura 600, 32px / 1.05): Secondary display moments —
  rank-tier numerals, large stat counters.
- **Headline** (Jura 700, 24px / 1.15, letter-spacing -0.02em): Screen titles
  and section H1s. The `-0.02em` tightens the negative space at large sizes.
- **Title** (Jura 600, 16px / 1.25): Section headers inside a screen, list-row
  primaries (class name, gym name, member name).
- **Title Soft** (Jura 400, 16px / 1.3, letter-spacing 0.03em): Title-weight
  text where the goal is body-density (long instructor names, descriptive
  lines).
- **Subtitle** (Jura 600, 13px / 1.3): Subsection headers, button text,
  dense-row primaries.
- **Body Large** (Jura 400, 16px / 1.4): Long-form copy — class descriptions,
  instructor bios. Cap line length at ~65–75 characters when long.
- **Body** (Jura 400, 12px / 1.4, letter-spacing 0.03em): The default in-app
  paragraph and metadata size.
- **Caption** (Jura 400, 11px / 1.35): Supporting metadata only — timestamps,
  tertiary labels. **Never** for anything the member must read to act.
- **Eyebrow** (Jura 700, 11px / 1.2, letter-spacing 0.24em, UPPERCASE): The
  small-caps label above and below `SparkleHero` accent numerals
  ("YOU EARNED", "POINTS"). Reserved for that one pattern.

### Named Rules

**The Single Family Rule.** The entire system runs on Jura. Pairing Jura with
a serif, a script, or a different sans is forbidden. Hierarchy is built from
weight and scale, not from font-family contrast.

**The Negative-Tracking Headline Rule.** The 24px Headline runs at -0.02em
letter-spacing. The 11px Eyebrow runs at +0.24em (i.e., true small-cap
treatment). Track for the size; never letter-space body or subtitle copy
beyond their token defaults.

**The Tap-Readable Rule.** The 11px Caption is for non-actionable metadata
only. If a member must read a string to decide or act on it, the floor is 12px
Body. Members range from teenagers to adults in their 50s, often reading in
variable gym lighting.

## 4. Elevation

CombatDen uses **no shadows.** Depth is conveyed through a single tonal
layer: the 10%-bone Surface Card over Canvas Black. Buttons render at
`elevation: 0`. The bottom nav is separated from the body by a 1px Bone Mute
hairline divider, not a shadow. The post-class scaffold uses the
`SparkleHero` orange-particle scatter to imply optical lift, but the underlying
surface is still flat — no blur, no glow, no `box-shadow`.

The doctrine: shadows imply consumer softness. CombatDen is not a wellness
app. Flat surfaces and a single tonal step do all the depth this system needs.

### Named Rules

**The Flat-By-Default Rule.** Every surface is flat at rest. There is no
shadow vocabulary. State changes communicate through color and border, not
through elevation.

**The No-Glassmorphism Rule.** No `backdrop-filter`, no blurred translucent
panels, no glass card decoration. The 10%-bone Surface Card is the only
allowed translucent surface, and it is not blurred.

## 5. Components

The member-facing component vocabulary leans on a tight set of primitives —
buttons, pills, cards, the bottom nav, and the signature `SparkleHero`. Every
one is built on the tokens above; new components extend the same scale.

### Buttons

The system has two button variants. Use `AppPrimaryButton` for the *one*
primary action on a screen; use `AppOutlineButton` for secondary or
non-committal actions.

- **Shape:** Primary uses 16px rounded corners (`rounded.sm`). Outline is a
  full pill (`rounded.pill`, 1000px).
- **Primary** (`AppPrimaryButton`): Cage Orange fill, Bone Text label, Subtitle
  type (Jura 600 / 13px), padding 16px horizontal × 8px vertical, no shadow,
  no border. Disabled state drops the orange to 50% alpha
  (`#FF6C2D80`).
- **Outline** (`AppOutlineButton`): Transparent fill, 2px Bone border, Bone
  Text label, Body type (Jura 400 / 12px), pill-rounded.
- **Hover / Pressed:** Native Material ripple over the button surface. No
  scale, no elevation change, no color flash.
- **Tertiary / Ghost:** Not part of the system. If a third level of emphasis
  is needed, use a plain text button styled as a link (Bone Soft) — do not
  invent a third button shape.

### Pills (Timeframe Selector)

- **Style:** 30px tall, 32px-rounded rectangle (it reads as a pill at this
  height). Active variant: 2px Bone border, Bone Text label at Title (Jura 600
  / 16px). Rest variant: no border, Bone Mute label at Title.
- **Use:** Time-range selectors only ("1W / 1M / 1Y" on stats, rank, points).
  Do not co-opt for tabs or filter chips.

### Cards / Containers

- **Background:** Surface Card (`#F4F3EE1A`, 10% bone over Canvas Black).
- **Corner Style:** 32px (`rounded.lg`) for screen-section cards; 16px
  (`rounded.sm`) for small inline containers.
- **Shadow Strategy:** None. (See section 4.)
- **Border:** None by default. If a card needs a border, use 1px Bone Mute as
  a hairline.
- **Internal Padding:** 16px (`spacing.lg`). Compact rows can drop to 8px
  (`spacing.md`) on the cross axis.

### Inputs / Fields

The visual prototype phase ships no production inputs yet; when added, follow
the system rules: Surface Card background, Bone Text input, Bone Mute
placeholder, focus state expressed as a Bone outline at 2px (the same border
weight buttons use). No glow, no inner shadow, no underline-only
("Material 2") inputs.

### Navigation

- **Bottom Nav** (`AppBottomNavBar`): 64px row, Canvas Black background, top
  edge a 1px Bone Mute divider. Four destinations (Home, Rank, Reward,
  Videos), each a Material Symbols sharp icon (weight 300) over a Caption
  label. Active state: Bone Text icon + label. Rest: Bone Mute. No fill, no
  pill, no underline indicator.
- **Topbar** (`AppTopbar`): When present, in-screen and scroll-bound — most
  screens put the topbar *inside* the scrollable rather than pinning it. Sits
  on Canvas Black, uses Headline type, optional avatar/back/close affordances
  via the icon system.
- **Mobile Treatment:** All nav is mobile-first. There is no desktop variant
  in scope.

### Signature: SparkleHero

The system's distinctive component, used **only** in the post-class scaffold
for streak / points / rank / rewards-unlocked moments.

- **Structure:** Three-line stack — top eyebrow ("YOU EARNED"), center accent
  numeral ("3,400"), bottom eyebrow ("POINTS").
- **Type:** Eyebrows render Jura 700 11px UPPERCASE letter-spaced 0.24em in
  Bone Soft. The accent renders Jura 700 64px in Cage Orange (Display Hero).
- **Decoration:** ~22 four-point sparkle marks scatter around the accent line
  on a fixed coordinate grid — outer-ring anchors at the screen edges, mid-field
  scatter, atmospheric specks. Sparkles are Cage Orange at varied alpha (0.35
  → 0.85). The scatter is hand-tuned, not procedural.
- **Background:** Canvas Black, no fill, no card. The decoration *is* the
  surface treatment.

### Named Rules

**The Single Primary Rule.** A screen has exactly one Primary button. If the
design seems to want two, one of them becomes an Outline.

**The SparkleHero Rationing Rule.** `SparkleHero` appears only inside the
post-class scaffold flow. Never on home, booking, profile, stats, video, or
rewards landing. Putting it elsewhere debases the celebration.

**The Sharp Icon Rule.** Every icon is `Symbols.<name>_sharp` at
`weight: 300`. Filled, rounded, or outlined Material variants are forbidden;
non-Material icon sets are forbidden.

## 6. Do's and Don'ts

### Do:

- **Do** keep Cage Orange (`#FF6C2D`) on ≤10% of any screen. Reserve it for
  primary actions, the active metric, and `SparkleHero` particles.
- **Do** layer with the Surface Card token (`#F4F3EE1A`, 10% bone over Canvas
  Black). It's the only tonal step the system has.
- **Do** use Jura for every text size. Build hierarchy from weight (400 / 600
  / 700) and scale (11 → 160), not from family contrast.
- **Do** use `Symbols.<name>_sharp` from `material_symbols_icons`, weight
  300, sized off the T-shirt scale (16 / 20 / 24 / 28 / 32 / 36).
- **Do** keep `SparkleHero` inside the post-class scaffold. It's the system's
  one loud moment; protect its rarity.
- **Do** treat the member like a practitioner. Coach-to-athlete copy:
  imperative, factual, outcome-named. "Reserve your spot", not "Get yours
  before they're gone!"
- **Do** keep `pSmall` (11px Caption) for non-actionable metadata only. If a
  member must read a label to act, the floor is 12px Body.
- **Do** use radius 16 for tight surfaces and radius 32 for screen-section
  cards. Use the full pill (1000) for outline buttons and timeframe pills.

### Don't:

- **Don't** use `#000` or `#fff`. Canvas Black is `#121619`, Bone Text is
  `#F4F3EE`. Pure black or pure white inside CombatDen is a bug.
- **Don't** ship gradient fills, gradient text, or
  `background-clip: text`. The system has none, and the `/impeccable`
  hero-metric template (big number + tiny label + supporting stats + gradient
  accent) is explicitly forbidden — quote PRODUCT.md's anti-cliché on this.
- **Don't** ship glassmorphism: no `backdrop-filter`, no blurred translucent
  panels, no glass cards. The single tonal layer (Surface Card at 10% bone) is
  not blurred.
- **Don't** ship `box-shadow`. Buttons render at `elevation: 0`. The bottom
  nav uses a 1px Bone Mute hairline, not a shadow. (See section 4: The
  Flat-By-Default Rule.)
- **Don't** ship side-stripe borders: no `border-left` or `border-right`
  greater than 1px as a colored accent on cards, list items, callouts, or
  alerts. (Per the `/impeccable` ban.)
- **Don't** nest cards. The Single Tonal Layer Rule: there is exactly one
  card surface. If hierarchy is needed inside, use type weight and
  dividers — not a second tonal layer.
- **Don't** introduce a second font. The Single Family Rule: Jura runs the
  entire scale, top to bottom.
- **Don't** ship the look-and-feel of generic fitness SaaS — MyFitnessPal,
  Fitbod, Strava-for-everyone. No teal/lime pastel accents, no cartoon
  mascots, no badges-as-stickers, no "Crush your goal!" copy. (Carried
  verbatim from PRODUCT.md anti-references.)
- **Don't** ship the wellness / mindfulness aesthetic — soft gradients,
  pastel everything, rounded blobs, "self-care" copy. Wrong sport, wrong
  audience.
- **Don't** ship em dashes. Use commas, colons, semicolons, periods, or
  parentheses. Also not `--`. (Per the global `/impeccable` ban and the
  CombatDen copy doctrine.)
- **Don't** `SparkleHero` outside the post-class scaffold. Putting it on
  home, booking, profile, stats, videos, or rewards-landing collapses its
  rarity and breaks "Post-class is celebration; in-app is clarity" (PRODUCT.md
  Design Principle 3).
- **Don't** invent a third button shape. The system has Primary (filled
  rectangle, 16r) and Outline (pill, 1000r). A third level is a styled link in
  Bone Soft, not a new component.
- **Don't** pull `motion` energy beyond ≤300ms ease-out on state changes. No
  bounce, no elastic, no spring. Reduced-motion is honored once wired (see
  PRODUCT.md Accessibility section).
