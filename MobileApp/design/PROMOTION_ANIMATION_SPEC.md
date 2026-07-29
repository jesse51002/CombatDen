# Belt-promotion animation — design spec

**Status:** DESIGN — not built. No file under `lib/` or `test/` was touched
writing this.

**Scope:** the moment the member app tells someone they moved up a rank. A new
celebration card (`PromotionScreen` + `PromotionBody`), the two new pure files
behind its watermark, and the changes to `celebration_flow.dart` /
`celebration_detector.dart` / `app_lifecycle_refresh.dart` that put it on
screen. The Profile tab's rank block, the topbar belt tile, the rewards card and
the rank card's own contents **do not change**; this spec only reuses their
parts.

**Contract it is designed against:** `MemberPortalPromotion` in
`../FastApiBackend/src/member_portal/schema/member_portal_schema.py`, carried as
the nullable `latest_promotion` on `MemberPortalProfile` — the payload the app
already loads. Read that docstring before implementing; every rule below quotes
it rather than restating it loosely.

---

## 0. What this has to be, in one paragraph

A member is promoted by staff from the ready-to-promote board, minutes to days
after a class and often in bulk. There is no honest way to attribute a promotion
to an attendance, so this is **not** a post-class card and its copy never
implies a class caused it. The member opens the app and the app tells them, once
per `activity_id`, showing the belt they came from becoming the belt they hold
now. Only genuine promotions arrive — the backend nulls demotions, lateral
corrections and unassignments — so the screen never has to hedge about
direction.

---

## 1. Where it plays

### The decision

**Its own full-screen card, pushed on app open / foreground, as the FIRST card
of the app-open celebration flow — composed by `celebration_flow.dart` like
every other card.**

Two claims there, argued separately.

#### 1.1 Its own card, not an addition to the post-class rank card

The post-class rank card only exists after a fresh staff check-in. A member can
be promoted without training that day, and often *is* — the ready-to-promote
board is worked in batches. If the promotion rode the rank card:

* A member promoted on a Tuesday who next trains the following Monday learns
  about their belt six days late, at the tail of a four-card flow.
* A member who is promoted and then stops training for a fortnight never learns
  at all.
* A **first assignment** — a rank-less member getting their first belt — cannot
  ride the rank card, because `celebration_flow.dart` composes the rank card out
  when the member holds no rank, and at the moment of a first assignment the
  *profile* now says they hold one but the promotion is the whole news.
* The rank card's job is progress *inside* a rank (`N classes in rank`,
  `X more classes until promotion`). A promotion resets both numbers to their
  least interesting values. Bolting the belt change onto a card that then says
  "10 more classes until promotion" ends the biggest moment in the app on a
  deflation.

So it is its own card, on its own route, driven by its own watermark.

#### 1.2 In the flow, not beside it — and first

`MobileApp/CLAUDE.md` is unambiguous: *"`celebration_flow.dart` owns the card
ORDER, and it is the only place that decides which cards a member sees… Add a
card by adding it to that list, not by hardcoding a route in a screen's CTA."*
A second, parallel detector pushing its own screen onto the same navigator on
the same app-open hook would be exactly the parallel implementation that rule
exists to prevent — and it would race the celebration push.

So the promotion is a **card in the composed list, at index 0**, and it inherits
every existing law for free: `celebrationCtaLabel` gives it "Continue" or
"Done"; `nextCelebrationCard` gives it its successor; the last card always
returns home; no screen hardcodes a label.

The flow's *concept* widens from "the post-class celebration" to "the app-open
celebration flow". The `postClass*` route and file **names stay** — they are the
route contract, not copy, the same law that keeps `AppBottomNavTab.rank` named
`rank` while it is labelled "Profile". `MobileApp/CLAUDE.md` §*The post-class
celebration is composed, not hardcoded* is rewritten in the same change (§14).

**Why index 0 and not last.** The peak-end argument for ending on the belt is
real and was considered. It loses on three counts:

1. A member can close the flow at any card (the `✕` is always live). Putting the
   biggest news last means the news is the reward for tapping through three
   cards about a class they may barely remember.
2. The promotion is the reason to open the app. Landing it on the first frame is
   the strongest open the product has.
3. **Decisive:** a promotion card sitting in the rank card's slot, immediately
   after "you attended a class" and "you earned N points", re-creates by
   adjacency exactly the class-caused-it reading the backend deliberately
   refused to encode. First, alone, before any class content, is the only
   position where the copy "You've been promoted" is not quietly contradicted by
   the layout.

### The collision answer

A promotion and a post-class celebration can both be pending on the same app
open. It is a minority case (the realistic sequence is: train → checked in →
open the app that evening, burning the celebration → promoted later), but it is
real, because the ready-to-promote board is populated *by* attendance.

**When both fire: the promotion plays first, the class flow continues behind it,
and the post-class RANK card is composed out.**

```
promotion → streak → points → [rewards] → (rank card SUPPRESSED) → wins → home
```

Suppressing the rank card is the load-bearing half of the answer:

* It would restate the belt the promotion screen just spent 2.6 seconds
  delivering — the member's *only* two belt moments in the app, back to back.
* Its own copy is `{N} more classes until promotion` over `classesSinceRank`,
  which a fresh promotion has just reset to 0. It would read as "you have the
  furthest still to go" thirty seconds after being told they arrived.

One belt moment per app open. Composed out at the source, per the app's own
law — never a destination that renders itself empty.

The four remaining combinations, for completeness:

| Promotion pending | Class pending | Flow |
|---|---|---|
| yes | yes | `promotion → streak → points → [rewards] → wins`; the promotion's CTA reads "Continue" |
| yes | no | `promotion` alone, CTA reads **"Done"**, returns home |
| no | yes | today's flow, byte-for-byte unchanged |
| no | no | nothing is pushed |

> **Note on the Wins card (landed in `b9c09fa8`, mid-spec).** `celebration_flow.dart`
> now appends `AppRoutes.postClassWins` unconditionally as the flow's closing
> nudge, and it owns its own themed book-next-class CTA rather than asking
> `celebrationCtaLabel`. Two consequences for this design, both handled in §8.1:
> wins must be gated on `classAttended` (a "Today's wins" recap of
> classes-this-week / points-earned / week-streak, ending in "book your next
> class", is a non-sequitur after a promotion on a day the member did not train),
> and the **promotion is now the second card that can be last** — so its CTA must
> route through `celebrationCtaLabel(nextCelebrationCard(...))`, never a hardcoded
> string.

### What it does NOT do

It does not fire from an arbitrary mid-session pull-to-refresh. The detector is
**armed** by the app-open / foreground hook and **consumed** by the first loaded
profile that arrives while armed (§8.2). A member reserving a class does not get
a full-screen takeover because staff happened to work the board at that instant;
they get it on the next foreground, which is seconds to hours later and is the
moment the app already owns.

---

## 2. The one idea: the belt is one object that changes identity

`RankBody` already owns the app's belt-motion vocabulary: a 280pt centred hero
belt that **physically interpolates** — `left` / `top` / `width` / `height`,
frame by frame, as a single rendered widget — into a `GlobalKey`-measured slot,
while the surrounding content cross-fades in around it. The belt is never
swapped for another widget; it is one object moving through space.

The promotion extends that sentence, it does not write a second one. **The belt
stays one object for the whole animation; only its identity changes.** The
motion material is continuity — a shared-element transform whose *content*
dissolves at the midpoint — not a flip, not a spin, not a card-turn, not a
wipe. Nothing in this app rotates, and a belt is not a playing card.

The whole design follows from one problem: **a cross-dissolve of two belts can
be invisible.** A stripe promotion may snapshot the same art on both leaves; a
legacy row may carry no art at all; two adjacent stripe images differ by a
thread of tape. So the swap beat fires **four simultaneous signals**, and any one
of them carries the moment alone:

| Signal | Always available? | What it says |
|---|---|---|
| Belt cross-dissolve | No — identical art degrades it to a no-op | the belt itself changed |
| Old rank NAME exits upward | Yes — names are non-null in every non-first-assignment case | you are no longer *that* |
| `SparkleBurst` fires | Yes | something good happened, here |
| Belt swells 1.0 → 1.06 → 1.0 | Yes | the change is *at this object* |

Colour is not a signal anywhere on this screen, which is what makes it safe
under white-labelling: `accent` and `primaryColor` are per-tenant slots and the
belt art itself is gym-uploaded.

---

## 3. The beat-by-beat timeline

One `AnimationController`, exactly as `RankBody`: `duration = A + B + C + D + E`,
phase progress derived from `_ctrl.value` inside a single `AnimatedBuilder`.
**No self-driving child animation is used for anything the skip must
fast-forward** (§10 explains why this matters and what it fixes).

### 3.1 Main case — both belts present

| # | Beat | Duration | Const | What moves |
|---|---|---|---|---|
| A | Enter | 420 ms | `_kEnter` | OLD belt: scale `0.5 → 1.0`, opacity `0 → 1`, at 280pt centred. OLD name label fades in on the same ramp. `Curves.easeOutQuart`. |
| B | Hold | 560 ms | `_kHold` | Nothing. The member reads the belt they know. |
| C | Swap | 360 ms | `_kSwap` | Constant-power cross-dissolve old→new; belt box swells to ×1.06 and back; OLD name fades out and translates −12pt; `SparkleBurst` mounts and starts. |
| D | Admire | 620 ms | `CelebrationTimings.sparkleWindow` | New belt held at 280pt while the sparkle scatter completes. Nothing else moves. |
| E | Settle | 700 ms | `_kSettle` | Belt interpolates `left/top/width/height` from centred-280 into the measured 154×100 slot; the settled block cross-fades in at `Opacity(settleE)`. `Curves.easeOutQuart`. |

**Total 2,660 ms**, then `markDone()` and `PostClassScaffold`'s 200 ms CTA fade
→ the member can act at **≈2.86 s**.

For calibration: `RankBody` is 1,920 ms, `PointsBody` 1,700 ms + cascade,
`StreakBody` ≈3,050 ms. This sits between the rank and streak cards, which is
where the app's biggest moment belongs.

Phase boundaries as fractions of `_ctrl.value` (total 2,660):

```
enterEnd   =  420 / 2660 = 0.1579
swapStart  =  980 / 2660 = 0.3684
swapEnd    = 1340 / 2660 = 0.5038
settleStart= 1960 / 2660 = 0.7368
```

Derive them in `build` from the `Duration` constants, the way `RankBody` does —
never type the fractions.

### 3.2 Beat C in detail — the swap

Let `t = swapT`, the raw linear 0..1 progress across beat C.

**Cross-dissolve — constant power, not linear opacity:**

```dart
final oldOpacity = math.sqrt(1 - t);
final newOpacity = math.sqrt(t);
```

Two images at opacity `a` and `1 − a` composited over the near-black canvas dip
in total luminance at the midpoint, and a mid-dissolve luminance dip on a dark
screen reads as a **flicker**, not a morph. The square-root pair holds combined
power roughly constant. This is the one place in the app where a non-eased
opacity curve is correct: a cross-dissolve of two co-located images has no
*arrival* to decelerate into, and easing it out would spend the first 100 ms
vanishing the old belt and the remaining 260 ms showing nothing change.

**Swell:**

```dart
final beltScale = 1 + 0.06 * math.sin(math.pi * t);
```

Symmetric, peaks at ×1.06 (≈17pt on a 280pt belt) at the midpoint, returns
exactly to 1.0. This is **not** a bounce or elastic curve — those overshoot a
target and oscillate around it, which the app bans. This is a deliberate swell
that ends where it started, and it is the app's own `pulseDuration` idea
(`_PulseOnLand` in `streak_day_badge.dart`) made symmetric because there is no
"landing" to punctuate, only a change.

**Old name exit:**

```dart
opacity:   1 - t
translate: Offset(0, -12 * t)
```

`12` is `StaggeredReveal`'s default `offset`, reused rather than re-picked. The
direction is **upward** because the member moved up; it costs nothing and it is
the same direction `CountUpText`'s digit reels travel when a number increases.

**Sparkles:** `SparkleBurst(size: _kHeroBelt)` is mounted the first frame
`_ctrl.value >= swapStart` (and never when `_skipped`, §10). It self-drives its
own 620 ms window — which is exactly why beat D is 620 ms and takes its duration
from `CelebrationTimings.sparkleWindow` rather than a new number.

Note: `SparkleBurst`'s particles fade **in and stay**. That is not a bug to work
around — it is how the wins card composes it (`Positioned.fill` behind the
trophy), and a residual scatter in the settled frame is the app's established
"this screen is a celebration" treatment. The belt travels ~40pt up and out of
the scatter's centre during beat E; with a ±150pt scatter radius the landed belt
is still comfortably inside the field, so nothing is orphaned.

### 3.3 First assignment — beats A and B are dropped

`old_rank_name` and `old_image_url` are both null. There is nothing to animate
*from*, so the screen renders an **arrival**, not a transition:

| # | Beat | Duration | What |
|---|---|---|---|
| A′ | Enter | 420 ms | NEW belt: `0.5 → 1.0` scale + fade at 280pt centred. `SparkleBurst` mounts at `t = 0` — the arrival *is* the celebration. |
| D | Admire | 620 ms | held |
| E | Settle | 700 ms | identical to §3.1 |

**Total 1,740 ms** + 200 ms CTA fade.

No old-name label is built (not built-and-hidden — not built). No swell, because
nothing swapped.

### 3.4 Degraded — the two belts would render identically

See §5.3 for the predicate. The **full §3.1 timeline runs unchanged**; only the
dissolve is a visual no-op because both `RankBeltImage`s resolve to the same
picture. The name exit, the swell and the sparkle burst all still fire, so the
beat still reads. This is the reason the swap carries four signals instead of
one.

---

## 4. The settled layout

### 4.1 Wireframes

**t = 0.42 s — end of beat A (main case)**

```
┌──────────────────────────────────────────┐
│                                       ✕  │  PostClassScaffold, always live
│                                          │
│                                          │
│              ╭──────────────╮            │
│              │              │            │
│              │  OLD  BELT   │  280 × 280 │  centred in the body rect
│              │              │            │
│              ╰──────────────╯            │
│                                          │
│           Blue Belt · 2 Stripes          │  h2 / text2nd
│                                          │
│                                          │
│                                          │
│   (no CTA — controller.isAnimating)      │
└──────────────────────────────────────────┘
```

**t ≈ 1.16 s — mid-swap**

```
┌──────────────────────────────────────────┐
│       ✦                               ✕  │
│           ✦         ✦                    │
│              ╭──────────────╮      ✦     │
│     ✦        │  old ⇢ new   │            │
│              │  (dissolve)  │   × 1.06   │
│       ✦      │              │        ✦   │
│              ╰──────────────╯            │
│          ✦                     ✦         │
│           Blue Belt · 2 Stripes  ↑       │  fading out, −12 pt
│               ✦           ✦              │
│                                          │
└──────────────────────────────────────────┘
```

**t = 2.66 s — settled**

```
┌──────────────────────────────────────────┐
│       ✦                               ✕  │
│           ✦         ✦                    │
│          YOU'VE BEEN PROMOTED      ✦     │  eyebrow: pSmall w700 caps, text2nd
│     ✦                                    │
│              ╭─────────╮                 │
│              │   NEW   │   154 × 100     │  the landed belt (measured slot)
│              ╰─────────╯           ✦     │
│          ✦                               │
│              Purple Belt                 │  h1 / text
│               ✦           ✦              │
│                                          │
│         from Blue Belt · 2 Stripes       │  h3 / text2nd
│  ┌────────────────────────────────────┐  │
│  │                Done                │  │  AppPrimaryButton, radiusBig, h2
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**First assignment, settled** — identical minus the bottom caption:

```
│           YOUR FIRST RANK                │
│              ╭─────────╮                 │
│              │   NEW   │                 │
│              ╰─────────╯                 │
│              White Belt                  │
│                                          │
│         (no "from" line — there is no    │
│          from; the Spacer takes it)      │
```

### 4.2 The structure

The settled block is `RankBody._StatsLayout`'s skeleton, verbatim — `Spacer` /
centred min-column / `Spacer` / bottom caption:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    const Spacer(),
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        CelebrationEyebrow(text: headline),
        SizedBox(key: slotKey, width: _kSlotWidth, height: _kSlotHeight),
        Text(newName, style: DesignConstants.h1, textAlign: TextAlign.center),
      ],
    ),
    const Spacer(),
    if (fromLine != null)
      Text(
        fromLine,
        textAlign: TextAlign.center,
        style: DesignConstants.h3.copyWith(color: DesignConstants.text2nd),
      ),
  ],
)
```

wrapped in `Opacity(opacity: settleE)`, with the animated belt overlaid as a
sibling `Positioned` in the same `Stack`. That is `RankBody`'s build tree with
different children.

### 4.3 The numbers, and why

**Hero size `_kHeroBelt = 280`** — verbatim `RankBody._kBigBelt`. Same
vocabulary, same number.

**Start scale `0.5`** — verbatim `RankBody._kBeltStartScale`, which is also
`ScaleReveal`'s default.

**Slot `_kSlotWidth = 154`, `_kSlotHeight = 100`** — exactly **2×**
`RankHeader`'s 77 × 50 belt. `RankBody` lands at 77 × 50 because on that card the
belt is a label beside a number; here the belt *is* the payload, and ending a
belt celebration on a 77pt thumbnail deflates it. Doubling keeps the aspect
identical (1.54), keeps the provenance obvious, and avoids inventing a free
number. It is a `_k` file constant per the CLAUDE.md carve-out for per-screen
layout maths.

**Why the name is stacked below the belt, not beside it (as in `RankHeader`).**
`old_rank_name` / `new_rank_name` arrive as ONE composed string that may include
the sub-rank — `Blue Belt · 2 Stripes`. **Never split it on the `·`**; it is a
display string from the server, and parsing display strings is how a gym with a
custom rank name breaks the layout. At `h1` (24 pt) that string measures ≈250 pt.
Beside a 154 pt belt with `spacingLarge` between them that is 154 + 16 + 250 =
420 pt, which overflows a 360 pt phone's 328 pt content width. Stacked, it has
the full 328 pt and fits on one line with room to spare. Stacking also matches
what the eye expects of a hero: mark, then name.

**`maxLines: 2`, `textAlign: center`, no `FittedBox`.** A gym with an unusually
long custom rank name wraps to two lines rather than shrinking; the app does not
auto-shrink type anywhere and should not start here.

**The eyebrow, not `SparkleHero`.** `SparkleHero` is the right *family* — it is
the app's post-class hero signature — but it is the wrong *component* here: it
self-animates on mount with no delay parameter (so "PROMOTED" would be legible
before the belt changes, spoiling the reveal), its `big1_5` accent at 64 pt
cannot hold a rank name, and its own sparkle field would fight `SparkleBurst`.
What is reused is its **eyebrow recipe** — `pSmall`, `w700`,
`letterSpacing: 0.24 × fontSize`, `text2nd`, all-caps — extracted so both files
share one implementation (§11).

**Why the words stay plain while the visuals go loud.** `PRODUCT.md`:
*"Coach-to-athlete voice… No exclamation-mark inflation, no aspirational
marketing prose"* and *"Post-class is the only place to be loud."* The sparkle
burst, the swell and the 280 pt belt carry the loud. `YOU'VE BEEN PROMOTED` is
the flattest possible true sentence, and that restraint is what makes the app
read as athlete tooling rather than a fitness app.

**When the settled words become legible.** `settleE` is `easeOutQuart`, which is
heavily front-loaded: at 20 % of the settle beat (140 ms in) it is already 0.59.
So the eyebrow and name are readable ~140 ms after the belt starts moving. No
second opacity ramp is needed, and the block stays a single `Opacity` exactly
like `RankBody`'s — one controller, skip-safe, nothing to desynchronise.

---

## 5. Every state, wired

| # | Condition | Card shown? | Timeline | Belt(s) | Eyebrow | Name | Caption |
|---|---|---|---|---|---|---|---|
| 1 | Both names + both images, images differ | Yes | §3.1 full | old art → new art | `YOU'VE BEEN PROMOTED` | `new_rank_name` | `from {old_rank_name}` |
| 2 | First assignment (`old_rank_name` **and** `old_image_url` null) | Yes | §3.3 | new art only | `YOUR FIRST RANK` | `new_rank_name` | *omitted* |
| 3 | Legacy row — both names, **both images null** | Yes | §3.1 (dissolve is a no-op) | themed `rankBelt` on both sides | `YOU'VE BEEN PROMOTED` | `new_rank_name` | `from {old_rank_name}` |
| 4 | One image null, one present | Yes | §3.1 full | themed slot ⇄ real art | as #1 | as #1 | as #1 |
| 5 | `old_image_url == new_image_url` (stripe with no per-sub override) | Yes | §3.1 (dissolve is a no-op) | one picture | as #1 | as #1 | as #1 |
| 6 | Stripe promotion, art differs by a hair | Yes | §3.1 full | near-identical art | as #1 | as #1 | as #1 |
| 7 | An image fails to load at runtime | Yes | as per its row | failing side falls back to themed → bundled | unchanged | unchanged | unchanged |
| 8 | `gymRankEnabled == false` | **No** | — | — | — | — | — |
| 9 | `latest_promotion == null` | **No** | — | — | — | — | — |
| 10 | `activity_id` present but `new_rank_name` null | **No** — watermark marked silently | — | — | — | — | — |
| 11 | Deep-linked (PR 3 push) with no live promotion | **No** — post-frame home | — | — | — | — | — |

### 5.1 State 2 — first assignment, in full

The schema is explicit that only the FROM side is genuinely optional: *"A first
assignment… has no leaf to have come from, so it arrives with the old side null
and the app renders an arrival rather than an animation out of nothing."*

This is **common at a new gym**, not an edge case — every member's first
grading hits it. It gets a designed screen, not a degraded one: the same belt at
the same 280 pt, the same sparkle burst, the same settle. The only differences
are that nothing dissolves, the eyebrow names what actually happened, and the
"from" line is absent rather than empty (`if (fromLine != null)` — an empty
`Text` would reserve a line of `h3` and push the block off centre, the same guard
`RankHeader` and `RankBody._RankRow` already apply to a blank sub-label).

### 5.2 State 3 — the legacy trap, and why the themed fallback is wrong here

The brief names it exactly: with both images null, the app's normal belt
fallback would put the **same** themed `CombatDenSlots.rankBelt` on both sides,
and the animation would dissolve one generic belt into the identical generic
belt. A 360 ms beat where nothing visibly happens reads as a broken app.

The answer is **not** to hide the belt or invent a placeholder. It is to
recognise that with no art the app has **no evidence the picture changed**, and
to let the words carry the change instead:

* One belt is rendered — the themed slot, then the bundled `stat_rank_belt.png`.
  It is not "the old belt" or "the new belt"; it is the app's generic mark for
  *a rank*, and the member has seen it in their own topbar.
* The swap beat still runs: the old name exits upward, the belt swells, the
  sparkles fire. Three of the four signals are intact.
* The settled frame states the change in full: `Purple Belt` over
  `from Blue Belt · 2 Stripes`.

Implementation-wise this needs **no branch**: the degrade predicate (§5.3) makes
the two `RankBeltImage` widgets resolve identically, and the identical dissolve
is harmless. Do not add a "legacy mode" — add the predicate only where it is
observable, which is nowhere in the widget tree.

### 5.3 The degrade predicate

```dart
/// True when the two sides would paint the same picture, so the cross-dissolve
/// is a visual no-op and the swap beat has to be carried by the name, the
/// swell and the sparkles alone.
bool get beltArtUnchanged {
  final a = oldImageUrl?.trim() ?? '';
  final b = newImageUrl?.trim() ?? '';
  return a == b; // covers both-empty (legacy) and same-url (stripe, no override)
}
```

Blank / whitespace-only is **absent, not broken** — the rule
`creatorAvatarProvider` and `RankBody._Belt` already set. The predicate exists
for tests and for the doc comment; **no widget branches on it**, because in every
case the correct rendering is "resolve each side independently and dissolve".

### 5.4 State 4 — one side missing

Each side resolves independently through the app's belt ladder. A null FROM with
a present TO dissolves the generic mark into the member's real new belt. That is
truthful about the present and merely non-specific about the past — the same
trade the topbar's belt tile already makes, and the member has never seen a
different picture for that old rank anyway (the gym never set one).

### 5.5 State 7 — a runtime load failure

`errorBuilder` → themed slot → bundled asset, per the app's law. The degrade
predicate is evaluated on URLs at build time and cannot see a runtime failure, so
a **double** failure produces an invisible dissolve. That is rare, graceful, and
still carries three of four signals. Do not build failure-coordination machinery
for it.

### 5.6 State 8 — the gym runs no ladder

`selectedMember.gymRankEnabled == false` composes the promotion card out at the
source in `celebrationCardRoutes` — the same gate that hides the rank card, the
`InfoBar` belt tile and the whole Profile rank block. The detector **does not
touch the promotion watermark** in this case: the gym has no rank surface, so
there is nothing to have been seen. Consequence, stated deliberately: if a gym
turns ranks back on, the member's most recent promotion is celebrated once at
that point. That is the right outcome — it is the app introducing them to the
ladder they are now on.

### 5.7 State 10 — a promotion with nothing to say

`new_rank_name` is the one string the copy cannot do without. The schema says it
is present in practice whenever the block is, so this is theoretical — but the
handling matters because getting it wrong creates a permanent re-evaluation
loop. **Mark the watermark and show nothing.** Marking (rather than skipping) is
what guarantees the unrenderable row can never be reconsidered on a later open.

---

## 6. Copy strings, complete list

| String | Where | Style |
|---|---|---|
| `YOU'VE BEEN PROMOTED` | eyebrow — states #1, #3, #4, #5, #6 | `CelebrationEyebrow` |
| `YOUR FIRST RANK` | eyebrow — state #2 | `CelebrationEyebrow` |
| `{new_rank_name}` | hero name | `h1`, `text` |
| `from {old_rank_name}` | bottom caption — every state but #2 | `h3`, `text2nd` |
| `Continue` / `Done` | CTA | from `celebrationCtaLabel(next)` — **never hardcoded** |
| `Belt promotion` | the DEBUG identity-sheet Developer row | `_DevRow` |

Notes on the choices:

* **`YOU'VE BEEN PROMOTED`, never "that class promoted you".** The backend
  docstring makes this a contract, not a preference. Nothing on this screen
  references a class, a date, or an attendance.
* **Apostrophe: ASCII `'`**, matching `"Who's training?"` — the app's other
  member-visible contraction. (The tree also contains `Today’s wins` with a
  typographic apostrophe; that inconsistency is flagged in §16, not resolved
  here.)
* **`from {old}` is lowercase and deliberately a fragment.** It continues the
  name directly above it, and the app's celebration captions are already
  lowercase continuations (`3,400 total points`, `3 more classes until
  promotion`). Sentence-casing it to `From …` would make it read as a new
  statement rather than a footnote to the name.
* **`YOUR FIRST RANK`, not `YOUR FIRST BELT`.** The app never says "belt" to a
  member today, and a gym on `sub_rank_type = 'div'` runs divisions, not belts.
  "Rank" is the term the whole system uses and it is true everywhere. See
  **OQ-1** — this is the one copy line worth a founder ruling.
* No exclamation marks, no em dashes, per `PRODUCT.md`.

---

## 7. The watermark

### 7.1 The rule

Two new pure files, mirroring `celebration_rules.dart` / `celebration_watermark.dart`
one for one. Read both before writing these; they are the precedent for
reinstall and second-device correctness and this must not drift from them.

`lib/features/stats/data/promotion_rules.dart`:

```dart
enum PromotionDecision {
  /// No watermark yet — SEED it silently to the current promotion and fire
  /// NOTHING, so a first run / reinstall / member switch never replays a belt
  /// the member was given months ago.
  seedSilently,

  /// A promotion the member has not seen — celebrate it once, then advance.
  fire,

  /// Already seen, or nothing to show.
  skip,
}

PromotionDecision decidePromotion({
  required String? lastSeenActivityId,
  required String? activityId,
}) {
  if (activityId == null) return PromotionDecision.skip;
  if (lastSeenActivityId == null) return PromotionDecision.seedSilently;
  if (activityId == lastSeenActivityId) return PromotionDecision.skip;
  return PromotionDecision.fire;
}
```

`lib/features/stats/data/promotion_watermark.dart` — `SharedPreferences` under
`promotion_watermark_<member_id>`, `lastSeen` / `mark`, both never throwing,
both logging on failure. A straight port of `CelebrationWatermark` with `String`
in place of `DateTime`.

### 7.2 The one difference from the celebration watermark, and why it matters

The celebration compares timestamps with `isAfter`. **The promotion compares ids
for equality.** `activity_id` is opaque and unordered — the schema calls it "an
opaque, immutable, unique id" and explicitly says a timestamp "would be a weaker
key (two rows can share an instant, and clock / precision differences across the
wire make equality fragile)".

Someone will try to make this ordered, or to key it on `promoted_at`. Both are
wrong, and the reason it is safe to be unordered is that **the server only ever
surfaces the newest genuine promotion**: a different id is by construction a
newer one. `promoted_at` is for display and ordering only and this screen does
not display it.

### 7.3 Seed-silently is what makes reinstall correct

A member who was promoted in March, reinstalls in July: `lastSeen` is null,
`activityId` is March's row → `seedSilently` → the watermark is written and
nothing is shown. A second device does the same on its first open. A member
switch is per-member-keyed and cannot cross-contaminate. Identical to the
celebration; do not deviate.

### 7.4 Advance before showing

`mark()` is awaited **before** the push, exactly as `CelebrationDetector` does
today, so the celebration fires exactly once and never replays even if the app
is killed mid-flow. The cost is that a promotion the member never actually
looked at is burned — accepted, and already the app's stated trade.

### 7.5 The DEBUG preview never advances it

The identity sheet's Developer row uses the same read path and **never** calls
`mark()`, mirroring `CelebrationDetector.fireNow`. A preview must not consume a
real promotion.

---

## 8. Composition and detection

### 8.1 `celebration_flow.dart`

```dart
List<String> celebrationCardRoutes({
  required bool promoted,
  required bool classAttended,
  required bool hasRewards,
  required bool rewardsWorthShowing,
  required bool rankEnabled,
  required bool hasRank,
}) {
  return <String>[
    if (rankEnabled && promoted) AppRoutes.promotion,
    if (classAttended) ...[
      AppRoutes.postClassStreak,
      AppRoutes.postClassPoints,
      if (hasRewards && rewardsWorthShowing) AppRoutes.postClassRewards,
      if (rankEnabled && hasRank && !promoted) AppRoutes.postClassRank,
      AppRoutes.postClassWins,
    ],
  ];
}
```

`classAttended` is new and load-bearing: without it, a promotion-only flow would
chain into the streak and points cards showing a stale week and **`+0 points`**
(`CelebrationData.empty().pointsWorth` is 0). Celebrating zero points is a false
statement about a class the member did not just attend. The same argument covers
the Wins card, which is otherwise unconditional: its three tiles are a recap of a
*class*, and its CTA is "book your next class". Grouping the four class cards
under one `if (classAttended)` spread is what keeps that guarantee visible in the
list rather than repeated four times.

`nextCelebrationCard` needs the same two facts, and only `CelebrationData`
threads screen-to-screen, so:

```dart
String? nextCelebrationCard({
  required String current,
  required CelebrationData data,
  required bool hasRank,
  required int? pointsBalance,
});
```

with `promoted: data.promoted` and `classAttended: data.occurredAt != null`
derived inside. `CelebrationData` gains **one** field, `final bool promoted`
(default `false`), and its doc comment widens from "the post-class celebration
flow" to "the app-open celebration flow". `classAttended` needs no new field —
`occurredAt` is already null on `CelebrationData.empty()` and on the PR-3
deep-link, which is exactly the "no class" case. Every existing call site stays
valid; the four celebration screens pass the `data` they already hold.

Degradation check: a card entered with no arguments falls back to
`CelebrationData.empty()` → `promoted` false, `occurredAt` null → the route list
is empty → `nextCelebrationCard` returns null → the CTA reads "Done" and returns
home. Correct for every card, including a deep-linked one.

### 8.2 `celebration_detector.dart`

One decision point, one push. The signature gains the loaded profile:

```dart
Future<void> maybeFire(NavigatorState? navigator, MemberProfile? profile) async
```

Sequence:

1. Guard on `selectedMember.memberId` / `.gymId`, and on `_inFlight`.
2. **Promotion leg** — `decidePromotion` against `profile?.latestPromotion`,
   skipped entirely when `!selectedMember.gymRankEnabled`. `seedSilently` and
   `fire` both `mark()`; only `fire` sets `promoted = true`. The unrenderable
   case (§5.7) marks and returns false. **No network call** — the promotion
   rides the profile that is already loaded.
3. **Class leg** — today's class-history read and `decideCelebration`, wrapped in
   **its own `try` / `catch`** that yields `classAttended = false` on failure.
   This is a change from today's single outer `catch`, and it is required: a
   class-history fetch failure must not swallow a promotion that needs no
   network at all.
4. Compose `celebrationCardRoutes(...)`. Empty → return.
5. `_primeRewards()` **only when `classAttended`** — the rewards card cannot
   appear otherwise, so a promotion-only flow does not fire a catalog fetch it
   will never read.
6. `navigator?.pushNamed(routes.first, arguments: data)` where `data` is the
   class payload (or `CelebrationData.empty()`), carrying `promoted:`.

Note on latency, stated rather than glossed: because the class leg is awaited
before composing, a **promotion-only** flow now waits on the same class-history
read the app already performs on every open. It is not new latency — it is the
existing beat at which the celebration already lands today — but it does mean
the belt appears at that beat rather than instantly. The alternative (push the
promotion immediately, resolve the class flow as a late gate à la
`CelebrationRewardsGate`) is a third async gate for a case measured in
milliseconds; see **OQ-3**.

### 8.3 `app_lifecycle_refresh.dart` — arm and consume

The promotion lives on the profile, and the profile is not loaded at the
post-frame callback. `AppLifecycleRefresh` already sits below the
`MemberProfileBloc` provider, so:

```dart
bool _armed = false;

// initState post-frame  → _armed = true
// didChangeAppLifecycleState(resumed) → dispatch refresh; _armed = true

BlocListener<MemberProfileBloc, MemberProfileState>(
  listener: (context, state) {
    if (!_armed) return;
    if (state.status != MemberProfileStatus.loaded || state.profile == null) {
      return;
    }
    _armed = false;                       // one check per app-open / foreground
    _celebration.maybeFire(
      widget.navigatorKey.currentState,
      state.profile,
    );
  },
  child: widget.child,
)
```

Why arm-and-consume rather than "check on every `loaded`":

* **It cannot re-fire on a silent refresh.** A mid-session pull-to-refresh emits
  `loaded` but the detector is disarmed, so nothing takes over the screen while
  the member is mid-booking. The house law — *the entrance plays once per mount
  and must never re-fire on a silent refresh* — is enforced at the push, not
  just inside the widget.
* **It still catches the app-open race.** The post-frame callback runs before the
  first profile lands; arming and waiting is what makes the promotion reachable
  on a cold start at all.
* **The watermark is the backstop, not the mechanism.** Even if the listener ran
  twice, `decidePromotion` would answer `skip`. Belt-and-braces on purpose.

One benign consequence: if a foreground's refresh returns a byte-identical
profile, `Equatable` suppresses the emission and the arm is never consumed. That
is correct — an identical profile carries no new promotion — and the arm simply
clears on the next real emission.

### 8.4 `PromotionScreen`

Modelled on `RankScreen` line for line:

* `BlocBuilder<MemberProfileBloc, MemberProfileState>`; `profile == null` holds
  on `ColoredBox(color: backgroundColor)` (transient — the flow only reaches
  here after a loaded profile).
* **The promotion is captured on first build into a `late final` field.** A
  silent refresh landing mid-animation must not be able to swap the belts under
  the member. This is the screen-level half of "never re-fire on a silent
  refresh"; the body's `initState`-driven controller is the widget-level half.
* Self-skip backstop: `latestPromotion == null` (or `gymRankEnabled == false`)
  → post-frame `pushNamedAndRemoveUntil(home)`, guarded by an `_endScheduled`
  flag so a rebuild cannot schedule it twice. Same asymmetry `RankScreen`
  documents: composition is what stops the normal flow landing here; the
  self-skip exists for PR 3's deep link.
* CTA: `celebrationCtaLabel(next)` where
  `next = nextCelebrationCard(current: AppRoutes.promotion, data: data, …)`.
  `onCtaPressed` is `pushReplacementNamed(next, arguments: data)` or `_toHome`.
  **No hardcoded label** — this is the exact bug `rank_screen.dart` shipped and
  had to fix.
* `onClose: _toHome`.

### 8.5 The DEBUG trigger

Both push destinations already have a Developer row because neither is reachable
by hand. The promotion is a third: a real one burns its watermark on first sight,
so without a dev row nobody can look at it twice.

Add `Belt promotion` (`Symbols.military_tech_sharp`) to `IdentitySheetDevSection`,
wired the same way as its siblings — dismiss the sheet FIRST, then push onto the
`NavigatorState` captured before the pop.

It pushes `AppRoutes.promotion` with `const CelebrationData(promoted: true)`.
The screen renders `latestPromotion` when present. When absent, and **only under
`kDebugMode`**, it synthesises a preview from the member's own `profile.rank` —
new side = their real current rank name and image, old side null — which
previews the **first-assignment** state truthfully with their real belt. With no
rank at all it falls through to the self-skip and pops home. A dev trigger that
silently does nothing on a fresh member is useless; a dev trigger that fabricates
a fake belt is a lie. This is the honest middle.

---

## 9. Belt resolution — do not invent a fifth rule

`MobileApp/CLAUDE.md`: *"every belt in the app resolves the member's own art
first; don't invent a fifth rule."* Four sites exist —
`InfoBar._Belt`, `RankHeader._Belt`, `NextRankBadge._Belt`, `RankBody._Belt`.

For the promotion, "the member's own art" is `old_image_url` / `new_image_url` —
snapshots taken at the moment of the change precisely so new belt art cannot
rewrite an old promotion. The ladder is therefore:

```
snapshot URL  →  themed CombatDenSlots.rankBelt  →  bundled assets/ranks/stat_rank_belt.png
```

which is `RankBody._Belt` exactly, including its blank-is-absent rule and its
deliberate absence of width/height (the parent sizes it frame by frame, and both
branches must hand the animation ONE widget that fills whatever box it is
given).

**So do not write a fifth `_Belt`. Extract the fourth.** `RankBody._Belt` +
`_ThemedBelt` move to `lib/shared/widgets/rank/rank_belt_image.dart` as a public
`RankBeltImage`:

```dart
RankBeltImage({
  required String? imageUrl,
  required String asset,
  String slot = CombatDenSlots.rankBelt,
})
```

`RankBody` then uses it and loses ~35 lines; `PromotionBody` uses it twice (once
per side). The `slot` parameter exists so `NextRankBadge` can adopt it later
without a fork — see §16, F-2. Net widget count for belts: **four, not five.**

---

## 10. Skippability and duration

### 10.1 The contract

`PostClassScaffold` + `PostClassController`, unchanged:

* While `controller.isAnimating`, the CTA is hidden and pointer-inert; a tap
  anywhere in the body calls `requestSkip()`.
* `PromotionBody` registers `_skipToFinal` in `initState`, clears it in
  `dispose`, and calls `markDone()` on natural completion via a status listener.
* The `✕` sits outside the body's `GestureDetector` and is live throughout.

### 10.2 Skip must be genuinely instant

```dart
void _skipToFinal() {
  if (!mounted) return;
  _skipped = true;      // BEFORE the jump — see below
  _ctrl.value = 1.0;
  widget.controller?.markDone();
}
```

`_skipped` is set **first** so the very next build does not mount `SparkleBurst`
on the jump frame. A skip means "stop the show, give me the answer"; a sparkle
scatter that *begins* animating after a skip is the opposite of what was asked
for.

This is the reason nothing on this screen is a self-driving child animation. A
`ScaleReveal` / `StaggeredReveal` / `CountUpText` child runs its own controller
off a `Future.delayed`, which `_ctrl.value = 1.0` cannot fast-forward. Everything
here — dissolve, swell, name exit, belt flight, block cross-fade — is derived
from the one controller value, so setting it to 1.0 paints the final frame in
full. The only self-driven thing is `SparkleBurst`, and it is suppressed rather
than skipped.

(`RankBody` does not currently hold this line — see §16, F-1.)

### 10.3 Durations, summarised

| State | Animation | + CTA fade | Actionable at |
|---|---|---|---|
| Main / degraded / stripe | 2,660 ms | 200 ms | ≈2.86 s |
| First assignment | 1,740 ms | 200 ms | ≈1.94 s |
| Skipped | 0 ms | 200 ms | ≈0.2 s |

Every per-element transition is ≤700 ms; every curve is `easeOutQuart` except
the two justified exceptions in §3.2 (a constant-power dissolve and a symmetric
swell). No bounce, no elastic, no overshoot, no idle motion, no loop. The
entrance plays once per mount.

---

## 11. File organisation

`PromotionBody` carries a five-phase timeline, two belts, an overlay name and a
settled block. Written as one file it would land around 260 lines — past the
~150-line rule. Split at construction:

| File | Contents | ~lines |
|---|---|---|
| `.../widgets/promotion/promotion_body.dart` | `PromotionBody` — controller, phases, `Stack`, slot measurement, skip | 145 |
| `.../widgets/promotion/promotion_settled_block.dart` | `PromotionSettledBlock` — eyebrow / slot / name / caption (§4.2) | 70 |
| `lib/shared/widgets/rank/rank_belt_image.dart` | `RankBeltImage` (extracted from `RankBody._Belt`) | 60 |
| `lib/shared/widgets/text/celebration_eyebrow.dart` | `CelebrationEyebrow` (extracted from `SparkleHero`'s inline recipe) | 30 |
| `lib/features/stats/data/promotion_rules.dart` | `PromotionDecision` + `decidePromotion` | 35 |
| `lib/features/stats/data/promotion_watermark.dart` | `PromotionWatermark` | 45 |
| `lib/features/profile/data/models/member_promotion.dart` | the model + `.g.dart` | 55 |

Both extractions are strictly reductive — each replaces a duplicate that would
otherwise be created, and each leaves its origin file shorter.

---

## 12. Tokens used — complete list

Colours: `text`, `text2nd`, `backgroundColor`, `primaryColor` (via
`SparkleBurst`'s own read).
Type: `h1`, `h2`, `h3`, `pSmall`.
Spacing: `spacingBig`, `spacingLarge`.
Radius: `radiusBig` (the CTA, via `PostClassScaffold`).
Icons: `iconWeight`, `iconSizeSm` (the DEBUG row), `Symbols.military_tech_sharp`.
Timings: `CelebrationTimings.sparkleWindow` (beat D).
Slots: `CombatDenSlots.rankBelt`.
Assets: `assets/ranks/stat_rank_belt.png` (via `ApiImage.rankAsset`).

`_k` file-scoped constants, permitted by the CLAUDE.md carve-out for per-screen
layout and timing maths:

```dart
const Duration _kEnter  = Duration(milliseconds: 420);  // = RankBody._kEntrance
const Duration _kHold   = Duration(milliseconds: 560);
const Duration _kSwap   = Duration(milliseconds: 360);
const Duration _kSettle = Duration(milliseconds: 700);  // = RankBody._kShrink
const double _kHeroBelt       = 280;   // = RankBody._kBigBelt
const double _kBeltStartScale = 0.5;   // = RankBody._kBeltStartScale
const double _kSlotWidth      = 154;   // = 2 x RankHeader's 77
const double _kSlotHeight     = 100;   // = 2 x RankHeader's 50
const double _kSwell          = 0.06;
const double _kNameExitRise   = 12;    // = StaggeredReveal's default offset
```

Beat D's duration is `CelebrationTimings.sparkleWindow`, not a `_k` — it is the
sparkle window by definition, not a number that happens to match it.

**No new `DesignConstants` token is added.** No colour, spacing, radius, border
or icon size is inlined.

---

## 13. Widgets and behaviour reused, not rebuilt

| Reused | From | For |
|---|---|---|
| The measured-slot belt flight (`GlobalKey` + `Positioned` `left/top/width/height` interpolation, `easeOutQuart`) | `rank_body.dart` | the settle beat, verbatim |
| `Opacity(settleE)` over the whole surrounding block | `rank_body.dart` | the settled block's reveal |
| `Spacer` / centred min-column / `Spacer` / bottom caption | `rank_body.dart` `_StatsLayout`, `points_body.dart` | the settled layout skeleton |
| `_Belt` / `_ThemedBelt` resolution ladder | `rank_body.dart` | `RankBeltImage`, both sides |
| `RankHeader`'s 77 × 50 belt geometry | `rank_header.dart` | the 2× slot's aspect and provenance |
| The blank-sub-label guard (`if (sub.isNotEmpty)`) | `rank_body.dart` `_RankRow`, `rank_header.dart` | the omitted "from" line |
| `SparkleBurst`, composed behind the hero (`Positioned.fill` first in the `Stack`, so the scatter sits *behind* the art) | `wins_body.dart` | the swap beat |
| `CelebrationTimings.sparkleWindow` | `celebration_timings.dart` | beat D's duration |
| `_PulseOnLand`'s `pulseDuration` idea | `streak_day_badge.dart` | the swell, made symmetric |
| `StaggeredReveal`'s `offset = 12` | `staggered_reveal.dart` | the name's exit rise |
| The eyebrow recipe (`pSmall` w700, `0.24 × fontSize` tracking, `text2nd`, caps) | `sparkle_hero.dart` | `CelebrationEyebrow` |
| `h3` / `text2nd` bottom caption | `rank_body.dart`, `points_body.dart` `_TotalCaption` | the "from" line |
| `PostClassScaffold` + `PostClassController` (skip, CTA fade, `✕`) | `shared/widgets/post_class/` | unchanged |
| `celebrationCtaLabel` / `nextCelebrationCard` / `pushReplacementNamed` chaining | `celebration_flow.dart` | the CTA and the chain |
| `CelebrationWatermark` / `celebration_rules.dart` shape | `features/stats/data/` | the promotion watermark, ported |
| `RankScreen`'s null-profile hold + `_endScheduled` self-skip | `rank_screen.dart` | `PromotionScreen` |
| `IdentitySheetDevSection`'s `_DevRow` | `features/member_select/` | the DEBUG trigger |

Nothing new is invented except the swap beat itself, which is the one moment
this screen exists for.

---

## 14. Files an implementer touches

**New**

1. `lib/features/profile/data/models/member_promotion.dart` (+ generated
   `member_promotion.g.dart`) — mirrors `MemberPortalPromotion`; every field
   nullable exactly as the schema declares, `activityId` and `promotedAt`
   required. Doc comment names the Pydantic schema, per the model rule.
2. `lib/features/stats/data/promotion_rules.dart`
3. `lib/features/stats/data/promotion_watermark.dart`
4. `lib/features/stats/presentation/screens/promotion_screen.dart`
5. `lib/features/stats/presentation/widgets/promotion/promotion_body.dart`
6. `lib/features/stats/presentation/widgets/promotion/promotion_settled_block.dart`
7. `lib/shared/widgets/rank/rank_belt_image.dart`
8. `lib/shared/widgets/text/celebration_eyebrow.dart`

**Modified**

9. `lib/features/profile/data/models/member_profile.dart` — add
   `final MemberPromotion? latestPromotion;` and regenerate `.g.dart`
   (`dart run build_runner build --delete-conflicting-outputs`; never hand-edit).
10. `lib/core/app_routes.dart` — `static const String promotion = '/promotion';`
    (a sibling of the `postClass*` family, not a member of it — it is not
    post-class).
11. `lib/main.dart` — one entry in `_routeBuilders`.
12. `lib/features/stats/data/celebration_data.dart` — `final bool promoted`
    (default `false`); widen the doc comment to "the app-open celebration flow".
13. `lib/features/stats/data/celebration_flow.dart` — §8.1.
14. `lib/features/stats/data/celebration_detector.dart` — §8.2, including the
    inner `try` / `catch` around the class-history leg and the conditional
    `_primeRewards()`.
15. `lib/features/login/presentation/widgets/app_lifecycle_refresh.dart` — §8.3.
16. `lib/features/stats/presentation/widgets/rank/rank_body.dart` — use
    `RankBeltImage`; delete `_Belt` and `_ThemedBelt`.
17. `lib/shared/widgets/sparkle_hero/sparkle_hero.dart` — use
    `CelebrationEyebrow` for its top and bottom lines.
18. `lib/features/stats/presentation/screens/streak_screen.dart`,
    `points_screen.dart`, `rewards_card_screen.dart`, `rank_screen.dart` — pass
    `data:` to `nextCelebrationCard`.
19. `lib/features/member_select/presentation/widgets/identity_sheet_dev_section.dart`
    and its host `identity_sheet.dart` — the `Belt promotion` row (§8.5).

**Tests**

20. `test/features/stats/data/promotion_rules_test.dart` — **new.** Null
    `activityId` → skip; null watermark → seedSilently; equal ids → skip;
    different ids → fire. Explicitly assert that a *lexically smaller* new id
    still fires, so nobody quietly makes it ordered.
21. `test/features/stats/data/promotion_watermark_test.dart` — **new.** Per-member
    keying; a write for member A does not satisfy member B; a corrupt / absent
    value reads as null and never throws.
22. `test/features/stats/data/celebration_flow_test.dart` — new params. Cases:
    promotion only → `[promotion]` exactly, so its CTA reads "Done"; promotion +
    class → rank card **absent** and wins still last; class only → today's list
    unchanged; `rankEnabled == false` + promoted → promotion absent;
    `classAttended == false` → streak, points, rewards **and wins** all absent
    (the wins case is the easy one to forget — it is unconditional inside a class
    flow).
23. `test/features/stats/presentation/widgets/promotion/promotion_body_test.dart`
    — **new.** Both-belts renders two `RankBeltImage`s; first assignment renders
    one and no "from" line; identical URLs still render the name exit; a skip tap
    reaches the final frame and never mounts `SparkleBurst`; the settled slot is
    154 × 100.
24. `test/features/stats/presentation/screens/promotion_screen_test.dart` —
    **new.** Null promotion → pops home once (not twice on rebuild); a profile
    refresh mid-animation does not change the rendered belts (the `late final`
    capture).
25. Existing celebration-flow / last-card tests — update for the new
    `nextCelebrationCard` signature.

**Docs (same change, per the living-document rule)**

26. `MobileApp/CLAUDE.md` — §*The post-class celebration is composed, not
    hardcoded* is rewritten: it is now the **app-open** celebration flow;
    the promotion is card 0 gated on `gymRankEnabled` + the promotion watermark;
    `classAttended` gates the four class cards; the rank card is additionally
    gated on `!promoted` and why. Add the promotion watermark beside the
    celebration watermark under *Live-session rules*. Add the third DEBUG row
    under *The two notification destinations have a DEBUG-ONLY trigger* (and
    rename that heading — there are three now). Note `RankBeltImage` under the
    belt-resolution rule so the "four sites" count stays honest.

**Verification**

`flutter analyze` clean; `flutter test` green; and a live run against a seeded
member through the DEBUG `Belt promotion` row in each of states #1, #2, #3, #5
and #6, plus one real staff promotion from the CRM to prove the watermark fires
once and only once, and one run with a promotion and a fresh check-in both
pending to prove the rank card is composed out.

---

## 15. Open questions

**OQ-1 — the first-assignment eyebrow.** This spec specifies `YOUR FIRST RANK`
over the uniform `YOU'VE BEEN PROMOTED`. The backend treats a first assignment as
a promotion, so uniform copy is defensible and simpler. Against it: "promoted"
with no "from" reads as a missing sentence to a white belt on day one, and this
is the *most common* state at a new gym, not an edge case. `RANK` over `BELT`
because a gym on `sub_rank_type = 'div'` runs divisions and the app says "belt"
to a member nowhere today. **Confirm the string.**

**OQ-2 — the settle target size.** 154 × 100 (2× `RankHeader`) is a judgement
call: large enough that a belt celebration does not end on a thumbnail, small
enough that the settled block reads as a composed frame rather than a still.
77 × 50 (identical to the profile, so the screen ends showing the member exactly
what their profile now looks like) is the alternative and has its own logic.
**Confirm 154 × 100 or ask for the smaller landing.**

**OQ-3 — whether the promotion should wait on the class-history read.** §8.2
composes both legs before pushing, so a promotion-only flow inherits the class
read's latency (the same beat the celebration already lands on today). The
alternative is to push the promotion the instant the profile lands and resolve
the class flow as a late gate the way `CelebrationRewardsGate` resolves the
rewards card — a proven pattern in this codebase, but a third async gate for a
saving of a few hundred milliseconds. **Not built. Ask if the delay is felt on a
real device.**

**OQ-4 — move the promotion decision to the identity read.** `latest_promotion`
rides the profile, which is right. But `MemberPortalIdentity` is fetched first
and cached, and the promotion is exactly the kind of "what shape is this app
open" fact the three capability flags already ride that payload for. If it moved
there, §8.3's arm-and-consume disappears and the promotion could be decided
synchronously at boot. That is a backend change and out of scope; raise it if a
second profile-dependent app-open moment is ever added, because a second one
would not be worth building this way.

**OQ-5 — should a promotion send a push?** The whole design assumes the member
opens the app. A member promoted on Friday who does not open the app until
Wednesday learns five days late. The FCM work (PR 3) is the obvious home for a
promotion notification, and `AppRoutes.promotion` is deliberately a real named
route with a self-skip backstop so a cold-start deep link already lands
correctly. **Out of scope; flagged so the route is not later assumed
unreachable.**

---

## 16. Findings outside this scope (flagged, not fixed)

**F-1 — `RankBody`'s skip does not actually skip everything.** `_skipToFinal`
sets `_ctrl.value = 1.0`, which jumps the belt and the stats cross-fade to their
final state — but `_CountBlock`'s `CountUpText(delay: _kEntrance + _kHold)` runs
its own controller off a `Future.delayed`, so after a skip the count-up still
fires ~1.2 s later and rolls for a further 1.4 s over an otherwise settled
screen. `markDone()` has already shown the CTA by then. The promotion screen is
specified to avoid this class of bug entirely (§10.2); `RankBody` should be fixed
the same way — derive the count from the controller, or fast-forward the child.
Not done here: it is a different card.

**F-2 — the four belt sites do not actually follow one rule.**
`MobileApp/CLAUDE.md` says all four resolve *member art → themed slot → bundled
asset*. `RankHeader._Belt` (`rank_header.dart:59-76`) skips the themed slot
entirely and falls straight to `profile_rank_belt_gold.png`. So the profile's own
belt ignores the tenant's `rank_belt` customization while the topbar three
honour it. Either the doc is wrong or the widget is; they disagree today. §9's
`RankBeltImage` (with its `slot` parameter) is the vehicle for collapsing all
four onto one implementation, but adopting it in the other three is a separate
change.

**F-3 — `SparkleBurst` has exactly one call site, and it moved during this spec.**
`wins_body.dart:89` (`Positioned.fill(child: SparkleBurst(size: 320))`) is the
only caller. That file was dormant when this design started and went live again
in `b9c09fa8`. This spec makes the promotion its second caller, which is the
right outcome either way — but the primitive's survival should not depend on one
card's fate. Worth a glance whenever the celebration flow is next reshaped.

**F-4 — `PostClassScaffold.header` has zero call sites.** All five celebration
screens pass no header. This spec also does not use it (the promotion's headline
belongs inside the body block so it cross-fades with the rest). It is an unused
public parameter on a shared widget — a delete candidate under *Always delete
dead code*, or a deliberate seam that should say so in its doc comment. Left
alone.

**F-5 — the app mixes ASCII and typographic apostrophes in member-facing copy.**
`"Who's training?"` (`member_select_screen.dart:35`) uses `'`;
`'Today's wins'` (`mock_stats.dart:136`, `celebration_stats_builder.dart:59`)
uses `’`. Two different glyphs on two screens a member sees in the same session.
This spec picks ASCII to match the picker. One of the two should win project-wide.

**F-6 — `StreakBody`'s icon pop uses `Curves.easeOutBack`.**
`streak_body.dart:213` — `easeOutBack` overshoots its target, which is precisely
what `PRODUCT.md`'s *"avoid bounce/elastic curves (per the `/impeccable` ban on
bounce)"* rules out, and what `ScaleReveal` / `StaggeredReveal` /
`CelebrationTimings` all document themselves as avoiding. Either the ban has a
deliberate exception nobody wrote down, or the streak icon should be
`easeOutQuart`. Flagged, not changed.

**F-7 — the celebration cards' `✕` is a ~32 pt tap target.**
`post_class_scaffold.dart:76-88` — `IconButton` with `padding: EdgeInsets.zero`
and `constraints: const BoxConstraints()` around an `iconSizeXl` glyph, so the
hit area is the icon. `PRODUCT.md` asks for ≥44 pt "where it doesn't fight the
layout", and in a top corner with nothing near it, it does not fight anything.
Affects all five cards including this one; fixed in one place.

**F-8 — `MemberProfile` will silently drop `latest_promotion` until §14 item 9
lands.** The backend already ships the field. `json_serializable` ignores unknown
keys, so today the app receives it and throws it away with no warning. Worth
knowing that "the animation does nothing" during implementation will most likely
be a forgotten `build_runner` run rather than a logic error.
