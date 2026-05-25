<!-- SEED — re-run /impeccable document once the redesign has code, to capture the actual tokens, generate the DESIGN.json sidecar, and replace the placeholders below. -->
---
name: AppManagement
description: Gym admin web app — a calm, premium control room for the member-retention engine.
---

# Design System: AppManagement

## Overview

**Creative North Star: "The Quiet Control Room"**

A dim, premium control room seen after hours. The surfaces are deep, desaturated slate;
nothing glows for its own sake. A single jewel-tone light draws the eye to the one thing that
needs attention right now: a retention signal trending the wrong way, a member due for a
rank promotion, a rewards balance about to convert. Authority comes from stillness and
restraint, not from alarm or athletic intensity. The owner glances at it between classes and
trusts it instantly.

This system is built for **legibility under glance**, not density. The retention engine
(attendance, ranks/divisions, points, rewards, content) is the subject; the chrome recedes so
the data reads in seconds. It is **vertical-neutral** by mandate: it must feel as right behind
a pilates studio as behind a BJJ gym, so it carries no combat-sports coding, no athletic
aggression, and no wellness-spa cliche.

It explicitly rejects the look of the incumbent gym CRMs (Mindbody, PushPress, Zen Planner),
the spreadsheet wall of uniform-weight data, and the generic Bootstrap-y SaaS dashboard. If a
viewer could say "a template made that," the screen has failed. Because these screens double
as a sales artifact, polish is load-bearing on every surface, including ones no one would
screenshot.

**Key Characteristics:**
- Deep desaturated slate base; warm-tinted neutrals, never pure black or white.
- One jewel-tone accent, used rarely and meaningfully.
- A single humanist sans; hierarchy from weight and scale, never from switching fonts.
- Restrained, responsive motion that degrades cleanly under `prefers-reduced-motion`.
- Calm, confident, credible. The opposite of a spreadsheet and the opposite of a neon dashboard.

## Colors

A near-monochrome slate field with one jewel-tone voice and a small, desaturated set of
semantic status hues for retention data. Exact values are resolved at implementation; the
*relationships* below are normative.

### Primary
- **Jewel Accent** `[to be resolved during implementation — candidates: deep emerald or sapphire; pick one, not both]`: the single point of attention. Active nav, the primary action on a screen, the one figure that matters most. Never decorative.

### Neutral
- **Deep Slate (background)** `[to be resolved]`: the room. Deep, desaturated, warm-tinted toward the accent hue (chroma ~0.005–0.01). Never `#000`.
- **Raised Slate (surfaces/containers)** `[to be resolved]`: one or two lightness steps above background for cards, panels, table rows that need separation.
- **Ink (primary text)** `[to be resolved]`: warm off-white, never pure `#fff`. Tinted toward the accent hue.
- **Muted Ink (secondary text / labels)** `[to be resolved]`: reduced-opacity ink for supporting copy, column headers, captions.
- **Hairline (borders/dividers)** `[to be resolved]`: low-contrast slate for full borders and 1px dividers only.

### Tertiary — Semantic Status (functional, not brand)
- **Good / On-track** `[to be resolved — desaturated green]`: retention healthy, streak alive, rank progressing.
- **Watch / At-risk** `[to be resolved — desaturated amber]`: attendance slipping, reward expiring.
- **Critical / Churn-risk** `[to be resolved — desaturated red]`: member likely to quit, action needed.
- These stay muted so they read as data, not alarm, and never compete with the Jewel Accent for "the one light."

### Named Rules
**The One Light Rule.** The Jewel Accent appears on ≤10% of any given screen. It marks the single thing that most needs the owner's attention. Its rarity is the signal: spend it and you spend the owner's eye. Status hues are functional and exempt, but they are desaturated so they never read as a second accent.

**The Tinted Neutral Rule.** No pure black, no pure white. Every neutral is tinted toward the accent hue (chroma 0.005–0.01). Pure greys read as the generic-SaaS dashboard this system rejects.

## Typography

**Display Font:** `[single humanist sans — family chosen at implementation]`
**Body Font:** same family.
**Label/Mono Font:** the same sans; tabular figures for numeric columns and metrics.

**Character:** One warm, humanist sans does all the work. Humanist (not geometric) so it reads as crafted and approachable rather than the cold geometric grotesque of generic SaaS. Calm, legible at small sizes, confident at large.

### Hierarchy
- **Display** (`[bold, large clamp, tight line-height]`): the one big figure or screen title. Used sparingly.
- **Headline** (`[semibold]`): section titles (the "Title → Content" boundary in the spacing cascade).
- **Title** (`[medium/semibold]`): card and group headers.
- **Body** (`[regular]`): default reading text; cap measured text at 65–75ch.
- **Label** (`[medium, slightly looser tracking, optional uppercase]`): table column headers, chips, metadata, captions. Use tabular figures wherever numbers align in columns.

### Named Rules
**The Weight-Not-Family Rule.** Hierarchy comes from weight and scale within the single family, never from switching typefaces. Keep ≥1.25 scale ratio between steps; flat scales read as a spreadsheet.

## Elevation

Mostly flat, with depth conveyed by **tonal layering**, not drop shadows. Slate surfaces step up in lightness as they come forward (background → raised surface → floating). Resting surfaces cast no shadow.

### Shadow Vocabulary
- **Floating only** `[exact value to be resolved]`: a soft, low shadow reserved for *transient* surfaces that genuinely leave the plane — menus, popovers, dialogs. Never on resting cards or table rows.

### Named Rules
**The Flat-At-Rest Rule.** Surfaces are flat by default; depth is a tonal step, not a shadow. A shadow is a response to transience (a thing floating above the page), never decoration. If a resting card has a drop shadow, it is wrong.

## Components

No component system has been built for the new direction yet (seed). The next scan-mode pass
should capture and re-skin the existing shared primitives in `lib/shared/widgets/` to this
spec — notably `AppDataTable` (the canonical table; do not handroll rows/dividers),
`app_primary_button` / `app_outline_button`, `app_search_box`, `filter_bar` / `filter_pills`,
`section_card`, `info_row` / `info_table`, `view_switcher`, and `app_shell` (the side nav).
Re-skin these; do not fork parallel versions.

## Do's and Don'ts

### Do:
- **Do** keep the Jewel Accent to ≤10% of any screen (the One Light Rule); let it mark the single most important thing.
- **Do** tint every neutral toward the accent hue; never use `#000` or `#fff`.
- **Do** build hierarchy from weight and scale in one humanist sans (the Weight-Not-Family Rule), with ≥1.25 scale steps.
- **Do** convey depth with tonal slate steps; keep resting surfaces flat (the Flat-At-Rest Rule).
- **Do** use the spacing cascade (`spacingLarge → spacingMedium → spacingSmall`) so gap size communicates relationship; split widgets at the Title→Content boundary.
- **Do** keep status hues desaturated so retention data reads as information, not alarm.
- **Do** respect `prefers-reduced-motion`: motion is responsive feedback (hover, expand, tab change), never required choreography.
- **Do** hold text and meaningful UI to WCAG AA contrast against the slate background.

### Don't:
- **Don't** look like the incumbent gym CRMs (Mindbody, PushPress, Zen Planner) — no dense, dated, operational back-office clutter.
- **Don't** produce spreadsheet density — walls of tiny, uniform-weight data with no hierarchy. The retention engine is read, not deciphered.
- **Don't** fall into generic SaaS admin — no Bootstrap-y grey cards, blue hyperlinks, default-everything dashboards, or the hero-metric-with-gradient cliché.
- **Don't** use combat-sports machismo — no fight imagery, cage motifs, or aggressive condensed display type. Off-brand for the generalized class-based-gym positioning.
- **Don't** use a colored `border-left`/`border-right` greater than 1px as an accent stripe; use full borders, background tints, or leading figures instead.
- **Don't** use gradient text (`background-clip: text`), decorative glassmorphism, or identical icon-heading-text card grids.
- **Don't** reach for a modal as the first thought; exhaust inline and progressive alternatives first.
- **Don't** add a second accent. If a screen seems to need one, the layout, not the palette, is the problem.
