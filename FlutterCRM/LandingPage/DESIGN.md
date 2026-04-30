---
name: CombatDen LandingPage
description: Combat-native marketing site that sells the retention layer to fighting-gym owners.
colors:
  mat-tape-orange: "#FF6C2D"
  den-ink: "#121619"
  den-ink-deep: "#0B0E10"
  surface-low: "#0A0C0E"
  surface-mid: "#0F1316"
  surface-high: "#1A1F23"
  bone: "#F4F3EE"
  bone-soft: "#F4F3EEB8"
  bone-faint: "#F4F3EE80"
  bone-ghost: "#F4F3EE40"
  divider: "#F4F3EE26"
  mid-gray: "#8A8F96"
typography:
  display:
    fontFamily: "'Jura', sans-serif"
    fontSize: "72px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Inter, sans-serif"
    fontSize: "clamp(48px, 7vw, 104px)"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Inter, sans-serif"
    fontSize: "44px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Inter, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
  label:
    fontFamily: "'Jura', sans-serif"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.12em"
rounded:
  card: "10px"
  pill: "999px"
spacing:
  hairline: "8px"
  tight: "16px"
  base: "24px"
  loose: "48px"
  section: "120px"
components:
  button-primary:
    backgroundColor: "{colors.mat-tape-orange}"
    textColor: "{colors.den-ink}"
    rounded: "{rounded.pill}"
    padding: "18px 32px"
  button-primary-hover:
    backgroundColor: "{colors.mat-tape-orange}"
    textColor: "{colors.den-ink-deep}"
    rounded: "{rounded.pill}"
    padding: "18px 32px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.bone}"
    rounded: "{rounded.pill}"
    padding: "12px 22px"
  card-default:
    backgroundColor: "{colors.surface-mid}"
    textColor: "{colors.bone}"
    rounded: "{rounded.card}"
    padding: "32px"
  card-accent:
    backgroundColor: "{colors.surface-high}"
    textColor: "{colors.bone}"
    rounded: "{rounded.card}"
    padding: "32px"
  nav-link:
    backgroundColor: "transparent"
    textColor: "{colors.bone-soft}"
    typography: "{typography.body}"
    padding: "12px 16px"
  nav-link-hover:
    backgroundColor: "transparent"
    textColor: "{colors.bone}"
    padding: "12px 16px"
---

# Design System: CombatDen LandingPage

## 1. Overview

**Creative North Star: "The Fight Card"**

The page should read like a fight poster, not a SaaS landing page. Bold typography carrying most of the weight, decisive black ground, one screaming accent that does not apologize for itself, and copy that names opponents (the buyer's pain) literally. Editorial energy — the kind of layout that gets pinned to a gym wall — applied to a marketing site.

The system is **opinionated, combat-native, and founder-direct**. It explicitly rejects everything that PRODUCT.md names as anti-references: generic gym SaaS (Mindbody/Kilo mint-and-teal lifestyle pages), AI-slop landing pages (purple gradients, three-column icon grids, hero-metric template, gradient text), and replacement-CRM positioning. If a design move could appear on any fitness software page, it is wrong for this one.

Density runs **moderate** — the page breathes, but emptiness is earned by hierarchy, not pasted in for "modern minimalism" reflex. The primary engine of difference is typography contrast (Jura display against Inter body, large-to-small ratio greater than 5×) plus the rarity of `mat-tape-orange`.

**Key Characteristics:**
- One accent, used sparingly — the orange's rarity is the point.
- Display type does the work — Jura at large sizes carries identity, Inter does the reading.
- Warm dark, never flat black — `den-ink` (#121619) is intentionally tinted toward warm; pure `#000` is forbidden.
- Surfaces layer by tone, not shadow — depth comes from elevation steps in lightness, not from drop shadows.
- Long lines are forbidden — body text caps below 75ch, headlines wrap with intent.

## 2. Colors

A warm-dark stage with one accent that earns every appearance. No secondary or tertiary palette — the system is a Restrained–Committed hybrid: neutrals plus one disciplined orange.

### Primary
- **Mat-Tape Orange** (`#FF6C2D`): The single accent. Used on the brand wordmark, primary CTAs, eyebrows above section headings, and chart stat numerals. Nowhere else. The color earns its weight by appearing rarely; flooding it dilutes the brand into "another orange-themed SaaS."

### Neutral
- **Den Ink** (`#121619`): The canonical page ground. Warm-near-black, intentionally tinted. Replaces `#000` everywhere — pure black is prohibited.
- **Den Ink Deep** (`#0B0E10`): Used on the topmost layer (nav, hero deep wells) where the page should feel slightly recessed. Alternative to a drop shadow.
- **Surface Low / Mid / High** (`#0A0C0E` / `#0F1316` / `#1A1F23`): The three-step elevation ramp. Cards, callouts, and pinned panels pick a rung; raising the rung is the *only* way to signal lift.
- **Bone** (`#F4F3EE`): Foreground text and the inverted-section ground. Off-white, never `#fff`. Sits at ~94% lightness with a warm tint — pure white burns under the orange.
- **Bone Soft** (`#F4F3EEB8` / 72%): Secondary text. Section descriptions, tagline copy.
- **Bone Faint** (`#F4F3EE80` / 50%): Tertiary text. Captions, small print.
- **Bone Ghost** (`#F4F3EE40` / 25%): Quaternary. Inactive nav, disabled states.
- **Divider** (`#F4F3EE26` / 15%): Hairlines and section rules.
- **Mid Gray** (`#8A8F96`): Reserved for non-bone secondary text on surfaces where a tinted bone would muddy.

### Named Rules

**The One Voice Rule.** `mat-tape-orange` appears on at most ~10% of any given screen. Eyebrows, the brand wordmark, primary CTAs, and stat numerals — that is the entire allowed inventory. If a fifth use case is being proposed, the answer is no.

**The No-Pure-Black, No-Pure-White Rule.** `#000` and `#fff` are forbidden. Use `den-ink` and `bone`. Pure black turns the orange neon, pure white burns under it. The warm tint is what makes the page look like a printed object instead of a screenshot.

**The Tonal Elevation Rule.** Lift is conveyed by stepping up the surface ramp (`surface-low` → `surface-mid` → `surface-high`), not by adding a `box-shadow`. Drop shadows on dark grounds read as 2014 Material; the page does not look like 2014 Material.

## 3. Typography

**Display Font:** Jura (with `sans-serif` fallback) — geometric, slightly technical, reads as combat-sports-graphic without going full stencil.
**Body Font:** Inter (with `sans-serif` fallback) — neutral workhorse, broad weight range, gets out of Jura's way.
**Mono / Label Font:** none. Jura at small sizes with high tracking does the label work.

**Character:** A two-voice system — Jura speaks loudly for the brand, numerals, and step counts; Inter handles every word the reader actually needs to read. Pairing inversion is the signature: where most pages put serif-display + sans-body, this page puts geometric-display + sans-body and lets Jura's rectangular shapes carry the combat-graphic energy.

### Hierarchy

- **Display** (Jura 700, 72px, line-height 1, letter-spacing −0.01em): Hero stat numerals (`+160`, `7×`, `$9k`), step numbers (`01`, `02`), and the brand wordmark. Never used for prose.
- **Headline** (Inter 600, clamp(48px, 7vw, 104px), line-height 1.05, letter-spacing −0.02em): The single hero H1 per page. Tightened tracking is part of the brand — generic Inter-600 does not look right at this scale.
- **Title** (Inter 600, 44–48px, line-height 1.15): Section H2s. One per section. Always paired with a small-cap orange eyebrow above.
- **Body** (Inter 400, 18px, line-height 1.55): Section descriptions, taglines, FAQ copy. Cap at 65–75ch. 16px appears only in nav and small-print contexts.
- **Label** (Jura 700, 14–18px, letter-spacing 0.12em, UPPERCASE): Section eyebrows, in-page chips, reward labels. Always uppercase, always tracked-out, almost always orange or bone-soft.

### Named Rules

**The Display-Numerals Rule.** Numerals (points, prices, stats, step counts) are set in Jura, not Inter. Inter's tabular figures look like a spreadsheet; Jura's numerals look like a fight poster.

**The Eyebrow-Then-Headline Rule.** Every section opens with a Jura uppercase orange eyebrow, then an Inter 600 headline below. The pattern is rhythmic across the page — break it once and the section reads as foreign content.

**The No-Gradient-Text Rule.** `background-clip: text` with a gradient is forbidden. Emphasis comes from weight, size, and color contrast. The page has one accent; do not stretch it into rainbow territory.

## 4. Elevation

The system is **flat-by-default with tonal layering**. Drop shadows are not used. Lift is conveyed by stepping up the surface ramp (`surface-low` → `surface-mid` → `surface-high`) and, where needed, by a 1px hairline divider at `divider` (15% bone). The three-step ramp gives enough depth without inventing a shadow vocabulary that would look out of register on `den-ink`.

The hero pulses a soft radial **glow** (concentric orange-tinted halos behind the headline) which is decorative atmosphere, not elevation. It does not return on subsequent sections.

### Named Rules

**The Flat-By-Default Rule.** No `box-shadow` on cards, buttons, or panels. Surfaces are flat; depth comes from tonal steps and (rarely) hairline strokes. If a design comp comes back with shadows, reject and rebuild with the surface ramp.

**The Glow-Is-Hero-Only Rule.** The orange radial glow appears in the hero and nowhere else. Repeating it under every section turns atmosphere into wallpaper.

## 5. Components

### Buttons
- **Shape:** Pill (border-radius `999px`). The pill is the brand's button shape. Square buttons read as a different system.
- **Primary:** `mat-tape-orange` ground, `den-ink` label. Inter 600, 13–15px, slight letter-tightening. Padding `18px 32px` desktop, `14px 22px` in nav. Used for the demo CTA only.
- **Hover / Focus:** Background drops one step toward `den-ink-deep` (subtle deepening of the orange against the ground), label stays. No transform, no shadow, no glow. Focus ring is a 2px orange offset on a 1px transparent inset (so the ring lives outside the pill, not on it).
- **Ghost (nav):** Transparent background, `bone-soft` label, same pill shape, smaller padding. Hover lifts label to full `bone`. Used for secondary nav actions.

### Cards
- **Corner Style:** `card` radius (10px). Soft, but not pillowy.
- **Background:** `surface-mid` for default, `surface-high` for the highlighted/featured pricing card. Never `den-ink` (cards must read as a layer above the page).
- **Border:** None at default. The accented pricing card adds a 1px `mat-tape-orange` ring at 45% opacity (`#FF6C2D73`) — the *only* place a colored stroke is allowed.
- **Internal Padding:** `loose` (48px) for content cards, `base` (24px) for tight ones. Padding is not negotiable per breakpoint — readability survives at the smaller value.
- **Shadow Strategy:** None (per Elevation). Lift comes from the surface step.

### Navigation
- **Style:** Sticky top, `den-ink-deep` ground with a 1px `divider` rule on scroll. 72px tall on desktop. Logo (Jura wordmark in mat-tape-orange) on the left, link cluster center, primary CTA right.
- **Typography:** Inter 600 14px for links. Letter-spacing default, no uppercase.
- **States:** Default `bone-soft`, hover `bone`, active `mat-tape-orange`. No underline — the color shift is the affordance.
- **Mobile:** Below 767px, the link cluster collapses behind a hamburger; the CTA shortens (`bookDemoShort`) but never hides. Touch targets must be ≥44px.

### Inputs / Fields
The site is a marketing surface; there are no live inputs on the page. If any are added (newsletter, demo form), they should follow: `surface-mid` ground, 1px `divider` border, `card` radius (10px), Inter 400 16px label, `mat-tape-orange` 2px focus border. Errors use `mat-tape-orange` for the message. Do not introduce a separate error red — the brand has one accent.

### Eyebrow + Headline Pair (signature)
The page's most repeated pattern. Jura 700 uppercase 14–18px in `mat-tape-orange`, tracked +12%, with 16–24px of breathing room below before the Inter 600 headline. Treat this pair as a single component — every new section gets one, and the spacing is non-negotiable.

### Reward / Stat Circle (signature)
A 160px circle in `surface-mid` with Jura 700 numerals at 54px in `bone` (or `mat-tape-orange` for emphasis). Used in the loyalty timeline. The circle's rarity is the point; do not turn it into a generic icon container.

## 6. Do's and Don'ts

### Do:
- **Do** use `mat-tape-orange` (`#FF6C2D`) only for the brand wordmark, primary CTAs, eyebrows, and stat numerals — at most ~10% of any screen.
- **Do** use `den-ink` (`#121619`) as the page ground, never `#000`.
- **Do** use `bone` (`#F4F3EE`) for foreground text, never `#fff`.
- **Do** convey lift through the `surface-low` → `surface-mid` → `surface-high` tonal ramp.
- **Do** open every section with a Jura uppercase orange eyebrow followed by an Inter 600 headline.
- **Do** set numerals (points, prices, stats, step counts) in Jura, not Inter.
- **Do** cap body line length at 65–75ch.
- **Do** keep CTA pills the same shape on every page — the pill is the brand button.
- **Do** show real numbers (1500pts ≈ 15 classes, 7× ROI). Specificity is the design move, not just the copy move.
- **Do** ensure tap targets are ≥44px on mobile, especially in the nav.

### Don't:
- **Don't** use mint, teal, or any "wellness" green — that is generic gym SaaS (Mindbody, Kilo, Gymdesk) and PRODUCT.md names it as anti-reference #1.
- **Don't** use purple/indigo gradients, three-column icon-in-circle feature grids, the hero-metric template, gradient text, or decorative blob graphics — the AI-slop reflex.
- **Don't** use `#000` or `#fff`. Forbidden.
- **Don't** apply `background-clip: text` with a gradient. The page has one accent; emphasis comes from weight, size, and the orange's rarity.
- **Don't** add `box-shadow` to cards, buttons, or panels. Lift is tonal.
- **Don't** stretch `mat-tape-orange` into a secondary or tertiary palette. One accent. One voice.
- **Don't** use `border-left` or `border-right` greater than 1px as a colored stripe on cards or callouts. Side-stripe borders are forbidden across the system.
- **Don't** copy generic SaaS section structures (testimonial rail, feature-grid-with-icons, "Trusted by" logo bar) without rebuilding them in this language. The default rendering of those patterns reads as Mindbody.
- **Don't** introduce a second display font. Jura carries display work. Two display fonts means the system has lost a fight with a designer's whim.
- **Don't** suggest "switch to us" or "replace your CRM" anywhere — visually or copy-wise. We are a layer that runs alongside; PRODUCT.md names this as anti-reference #3.
- **Don't** ship animation that runs against `prefers-reduced-motion`. The orbital arcs, the scroll-driven counters, and the auto-advancing loop must short-circuit when the user opts out. (Current build does not honor this — known gap.)
