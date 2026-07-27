# Post-class Rewards card — affordability design spec

**Status:** BUILT — shipped in "Rewards card says which rewards the member can
actually get". Kept as the design RECORD: the reasoning here (why `accent` and
not `primaryColor`, why the featured size can't grow, why catalog order is
preserved) is not recoverable from the diff. Two known drifts from the shipped
code: the float-drift claim behind the integer comparison is wrong (`0.9 * 1000`
is exactly `900.0`; the integer form is kept because it is exact by
construction), and the reserved caption heights were raised and turned into
minimums after the specified values overflowed.

**Scope:** the post-class celebration's Rewards card only —
`lib/features/stats/presentation/screens/rewards_card_screen.dart`,
`lib/features/stats/presentation/widgets/rewards/**`, plus the flow-composition
files named in §7. The Rewards tab store (`lib/features/rewards/presentation/`)
**does not change**; this spec only *reads from* and *reuses* it.

---

## 0. What the founder asked for

1. "we need to know which one they can actually get and which is progressing
   towards, it needs to be clear visually"
2. "if you dont have enough for it it should be `x/x points`"
3. "if they cant get anything the page shouldnt be shown unless they are 90% to
   one" — read as ≥90% of the **cheapest** reward's cost.

Everything below serves those three, under `MobileApp/CLAUDE.md` and
`MobileApp/PRODUCT.md`.

---

## 1. The one idea: the frame is the progress meter

The reward slide already draws a **3pt `text`-coloured ring** around its 3:2
photo (`_RewardSlideImage`, `Border.all(color: text, width: buttonBorderSize)`).
Today that ring is decoration and carries no meaning. It becomes the meter.

This is a direct reuse of the app's existing "progress toward a thing" language,
not a new one. `NextRankBadge` (`lib/features/profile/presentation/widgets/
next_rank/next_rank_badge.dart`) is *art + a `text`-coloured `buttonBorderSize`
progress stroke around its frame*, drawn from the top, clockwise, with
`StrokeCap.round`. The reward slide is the same widget shape with a rounded
rectangle instead of a circle. Same tokens, same start point, same direction,
same cap.

| Slide state | Ring |
|---|---|
| **Redeemable** (`cost <= balance`) | Ring **closed**, `accent`, `buttonBorderSize` |
| **Locked** (`cost > balance`) | Hairline `divider` @ `dividerThickness` track for the full perimeter, plus a `text` @ `buttonBorderSize` stroke covering `balance / cost` of it, from top-centre clockwise |
| **Unknown** (no balance, or bundled fallback slides) | Ring **closed**, `text`, `buttonBorderSize` — **byte-identical to today's shipped look** |

Why this and not a new bar/ring/meter: the house rule says find the existing
expression of "progress toward a thing" and reuse its visual language.
`NextRankBadge` is it. Adding a separate bar under the photo would be a second,
competing progress vocabulary in the same app.

Why it satisfies "colour must not be the only signal": *closed vs. open* is a
pure shape signal, legible in greyscale and at the 0.56 neighbour scale. Colour
is the fourth signal, after ring closure, tag presence (§2), and caption form
(§3).

Why `accent` and not `primaryColor` for redeemable: `DesignConstants` states the
rule outright — accent is the **selection / active-state** colour ("where you
are"), primary is **agency** ("what to tap"). Affordability is a state, and on
this card there is nothing to tap per reward (redeeming happens in the store).
This is exactly the reasoning `ClassReservedTag` records for "the member holds
this occurrence". Points keep `primaryColor` because points are orange
everywhere already (`RewardPointsCost`, `PointsHeadline`) — that stays untouched.

**White-label caveat, and why it does not sink the design:** `accent` is a
per-tenant brand slot. At some gyms it may land close to `text` or to
`primaryColor`. The design therefore never relies on hue: closure, tag presence
and caption wording each carry the distinction alone.

---

## 2. The slide

Geometry is **unchanged**: `_featuredSize = 208`, `_featuredAspect = 1.5`
(→ 138.67pt tall), `viewportFraction: 0.45`, `_minScale = 0.56`,
`_maxTilt = 0.6`, `radiusBig` corner, `BoxFit.cover`, `Clip.antiAlias`.

**Do not raise `_featuredSize`.** It is already at the geometric limit: with
`viewportFraction: 0.45`, the featured slide and its neighbour just touch at
`width = (screenWidth * 0.45) / 0.78`, which is 207.7pt on a 360pt-wide phone.
Any bump makes the *right* neighbour overlap the featured slide, and a
`PageView` paints later pages on top, so the neighbour would cover the hero.
The vertical-balance fix comes from §5 instead.

New on the slide, both pinned inside one top row:

```
 ┌────────────────────────────────────────┐  ← ring (state per §1)
 │ ┏━━━━━━━━━┓                 ┏━━━━━━━━┓ │
 │ ┃ ✓ Ready ┃                 ┃  Free  ┃ │  ← RewardReadyTag | RewardPriceTag
 │ ┗━━━━━━━━━┛                 ┗━━━━━━━━┛ │
 │                                        │
 │            gym's 3:2 photo             │
 │                                        │
 └────────────────────────────────────────┘
```

* **`RewardPriceTag`** — reused **verbatim** from
  `lib/features/rewards/presentation/widgets/reward_card/reward_card.dart`,
  pinned exactly where `RewardImageHero` pins it (`top: spacingMedium`,
  `right: spacingMedium`). This is the compose move that finally makes the
  celebration slide and the store's `RewardImageHero` the *same object*: same
  3:2, same `radiusBig`, same tag, same position. It also lets the caption drop
  its 24pt discount line (§3), which is where the vertical balance is won.
* **`RewardReadyTag`** — new, **only on redeemable slides**, pinned top-left at
  the same insets. Its absence is the locked signal on the slide.

Both tags are children of `_RewardSlideImage`, so the cover-flow 3D transform
carries them: on neighbour slides they scale to ~0.56 and tilt, reading as
coloured chips rather than text. That is correct — the neighbours are depth, and
an accent chip visible on a neighbour is precisely the "which ones can I get"
glance the founder asked for.

Layout for the two tags (handles a long `price_label` without either tag
overflowing):

```dart
Positioned(
  top: DesignConstants.spacingMedium,
  left: DesignConstants.spacingMedium,
  right: DesignConstants.spacingMedium,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (redeemable) const RewardReadyTag(),
      const Spacer(),
      Flexible(child: RewardPriceTag(label: priceLabel)),
    ],
  ),
),
```

Measured worst case: `Ready` tag ≈ 74pt + a long `price_label` ≈ 70pt + 2×8pt
insets = 160pt of 208pt. `Flexible` lets an unusually long label wrap rather
than overflow.

### `RewardReadyTag`

New file:
`lib/features/rewards/presentation/widgets/reward_card/reward_ready_tag.dart`.

It lives **beside `RewardPriceTag`, not in `lib/shared/widgets/`** — the one
place this spec chooses feature-local over shared. Reason: it is that tag's
sibling (same geometry, same pin family, same domain), and keeping the two
reward tags in one folder is what stops them drifting apart. It is also then
already available to the store if the store ever wants it.

Geometry copies `RewardPriceTag` exactly; only the fill and content differ:

```dart
Container(
  padding: EdgeInsets.symmetric(
    horizontal: DesignConstants.spacingMedium,
    vertical: DesignConstants.spacingTiny,
  ),
  decoration: BoxDecoration(
    color: DesignConstants.accent,
    borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    spacing: DesignConstants.spacingSmall,
    children: [
      Icon(
        Symbols.check_sharp,                       // ClassReservedTag's glyph
        weight: DesignConstants.iconWeight,
        size: DesignConstants.iconSizeXs,
        color: DesignConstants.backgroundColor,    // see Open Question OQ-1
      ),
      Text(
        'Ready',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.backgroundColor,  // see Open Question OQ-1
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
)
```

It is **solid-filled, not the `ClassReservedTag` 10%-tint recipe**, because it
sits on an arbitrary gym photo: a 10%-alpha fill over a bright upload would make
the accent glyph and label unreadable. `RewardPriceTag` solves the same problem
the same way. The tint recipe is right on the canvas (`ClassReservedTag`) and
wrong on a photo.

### The ring painter

Replace `_RewardSlideImage`'s `BoxDecoration.border` with a
`CustomPaint(foregroundPainter: _RewardRingPainter(...))` wrapping the clipped
photo container, so the ring paints over the photo edge.

```dart
class _RewardRingPainter extends CustomPainter {
  _RewardRingPainter({
    required this.progress,     // 0..1
    required this.ringColor,    // accent | text
    required this.trackColor,   // null when the ring is closed
  });
  ...
}
```

Path construction — built manually so it **starts at top-centre and runs
clockwise**, which makes `extractPath(0, len * progress)` exactly right with no
start-offset fudging and no wraparound branch:

```dart
Path _ringPath(RRect r) {
  final rad = r.tlRadiusX;
  return Path()
    ..moveTo(r.center.dx, r.top)
    ..lineTo(r.right - rad, r.top)
    ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
    ..lineTo(r.right, r.bottom - rad)
    ..arcToPoint(Offset(r.right - rad, r.bottom), radius: Radius.circular(rad))
    ..lineTo(r.left + rad, r.bottom)
    ..arcToPoint(Offset(r.left, r.bottom - rad), radius: Radius.circular(rad))
    ..lineTo(r.left, r.top + rad)
    ..arcToPoint(Offset(r.left + rad, r.top), radius: Radius.circular(rad))
    ..lineTo(r.center.dx, r.top);
}
```

`arcToPoint` defaults (`clockwise: true`, `largeArc: false`) are correct for a
90° corner. `radiusBig` (32) fits: `2 × 32 = 64 < 138.67`.

Paint rules:

* `rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radiusBig))`
  **deflated by `buttonBorderSize / 2`**. A `Border.all(width: w)` paints inward
  from the box edge; a stroke of width `w` centred on a rect deflated by `w/2`
  occupies the identical band — so the unknown state is pixel-identical to what
  ships today.
* Every paint: `style: PaintingStyle.stroke`, `strokeCap: StrokeCap.round`
  (matching `_ProgressArcPainter`).
* `trackColor != null` → `drawPath(_ringPath(rrect), trackPaint)` with
  `strokeWidth: DesignConstants.dividerThickness`.
* `progress >= 1.0` → `drawPath(_ringPath(rrect), ringPaint)` with
  `strokeWidth: DesignConstants.buttonBorderSize`. (Closed ring takes the cheap
  exact path; no path metrics.)
* `0 < progress < 1` → `final m = _ringPath(rrect).computeMetrics().first;`
  `drawPath(m.extractPath(0, m.length * progress), ringPaint)`.
* `shouldRepaint` compares `progress`, `ringColor`, `trackColor`.

**Deliberately mirrors** `_ProgressArcPainter` in `next_rank_badge.dart` — same
tokens, same start, same direction, same cap. It is a separate class only
because the geometry is an RRect, not a circle. A comment in the file must say
so, and name the sibling.

### Image failure

`_RewardSlideImage`'s `errorBuilder` stays exactly as it is:
`ColoredBox(color: DesignConstants.card)`. The ring and the tags are drawn
*outside* the clipped photo, so a failed image still carries its full
affordability state. Do **not** improve the placeholder here — the store's
`RewardImageHero` has the identical `errorBuilder`, and diverging would break
the "one uploaded photo is framed identically on both surfaces" law for the
benefit of one screen. See Finding F-4 for the out-of-scope fix.

---

## 3. The caption

Two blocks, both height-reserved so the auto-advance can never shift the stack.

```
              Bring a friend                ← h1, 1 line, ellipsis
                 800 pts                    ← h1, primaryColor
             ✓ Ready to redeem              ← h2, accent (redeemable only)
```

```
               Gym t-shirt                  ← h1, 1 line, ellipsis
            120 / 2,200 points              ← h2Regular, text2nd
```

| Block | Redeemable | Locked | Unknown |
|---|---|---|---|
| Name | `h1`, `maxLines: 1`, ellipsis, centred | same | same |
| Value | `'{cost} pts'` in `h1.copyWith(color: primaryColor)`, wrapped in `_PulsePoints` | `'{balance} / {cost} points'` in `h2Regular.copyWith(color: text2nd)`, **no pulse** | `'{cost} pts'` in `h1` + `primaryColor`, `_PulsePoints` — today's line exactly |
| State line | `Row(mainAxisSize.min, spacing: spacingSmall)` of `Icon(Symbols.check_sharp, accent, iconSizeSm, weight: iconWeight)` + `Text('Ready to redeem', h2.copyWith(color: accent))` | absent | absent |

* `'{balance} / {cost} points'` is `NextRankSection`'s `'$done / $target classes'`
  form and typography (`h2Regular` + `text2nd`) transposed to points. That is
  the founder's "`x/x points`", expressed in the app's own existing progress
  sentence rather than a new one.
* Both numbers go through `formatRewardPoints` from `reward_card.dart` (thousand
  separators), **not** the local `_formatPoints` — see Finding F-1.
* The pulse (`_PulsePoints`, key `'pts-$featuredIndex'`) fires **only** on the
  redeemable and unknown branches. It is a celebration beat; pulsing a shortfall
  would celebrate the gap.
* **What went away:** the `discountLabel` line (`h1Regular` @ 24pt, `text3rd`).
  It moves onto the slide as `RewardPriceTag`, where the store already puts it
  and where the eye already is. This is where 39pt of caption mass is recovered.

**Reserved heights** (the `RewardCard._kCardTitleHeight = 42` idiom, same file
family, same reason):

```dart
const double _kCaptionNameHeight = 31;       // one line of h1 (24pt × ~1.3)
const double _kCaptionValueHeight = 56;      // h1 line + spacingSmall + h2 line
```

Each block is `SizedBox(height: …, child: Align(alignment: Alignment.topCenter,
child: …))`, so the shorter locked/unknown value block sits high and the slack
falls below. Total caption = 31 + `spacingMedium` + 56 = **95pt**, constant
across every slide and every state. The `AnimatedSwitcher` (unchanged,
`duration: _slideDuration`, `key: ValueKey(featuredIndex)`) then cross-fades
between two same-sized children, which is what stops the vertical jump.

**Where the balance comes from:** `MemberProfileBloc` →
`state.profile?.retention.pointsBalance`. Confirmed by reading
`lib/features/rewards/presentation/widgets/store_grid/store_grid.dart:86-87`,
which gates the store's Redeem button on exactly that expression, and
`lib/features/profile/data/models/billing_retention.dart`. `RewardsCardScreen`
already has a `BlocBuilder<MemberProfileBloc, MemberProfileState>` in its tree,
so no new provider or fetch is needed.

**Null balance is UNKNOWN, never zero.** `profile` is null while the shared
profile is loading, and after an error with no last-good value. Rendering
`0 / 2,200 points` would be a false statement about a member who may have 3,000
points. The unknown branch is today's shipped look, so the degraded state is a
state the app has already shipped and nobody can be misled by it.

---

## 4. Title and subtitle, by card state

Today these come from `mockRewardsStats.title` / `.subtitle` — demo constants
applied to a live catalog. They become derived.

| Card state | Title (`big2`) | Subtitle (`pBig`, `text3rd`, `maxLines: 1`, ellipsis) |
|---|---|---|
| ≥1 affordable | `Rewards you can get` | `{n} reward ready to redeem` / `{n} rewards ready to redeem` |
| 0 affordable, ≥90% to cheapest | `Almost there` | `{gap} points to go` |
| Unknown (no balance, or bundled fallback slides) | `Rewards you can get` | `Swipe to view rewards` |

`gap = cheapestCost - balance`. Because the card is only shown at ≥90%, `gap` is
by construction ≤10% of the cheapest reward — a small, concrete, one-more-push
number. That is the answer to "what is the emotional read": the card leads with
a **distance**, not a denial, and the featured slide underneath it is the exact
reward that distance refers to, with a ~90%-closed ring. The member reads "you
are nearly there on this specific thing", never "you still can't have anything".

The subtitle deliberately does **not** name the reward (`'{gap} points from
{name}'` was considered and dropped): the featured caption directly below
already shows the full name, so naming it twice wastes the line and risks
truncation.

**Copy note (needs a nod):** today's title is Title Case (`'Rewards You Can
Get'`); this spec sets sentence case (`'Rewards you can get'`) to match the
app's other card title (`mockWinsStats.title = "Today's wins"`) and
PRODUCT.md's plain coach voice. If the founder prefers the existing casing,
use `'Rewards You Can Get'` / `'Almost There'` — nothing else changes.

Checked against PRODUCT.md's voice rules: imperative/factual, no exclamation
marks, no em dashes, no "you got this" hype.

---

## 5. Vertical balance

The problem: `PostClassScaffold` puts the body in `Expanded(child: Center(child:
body))`, and `_CarouselLayout` returns a `Column(mainAxisSize: MainAxisSize.min)`.
When the slide was a 208pt circle the block was ~440pt; at 3:2 the carousel band
dropped to 138.67pt and the block is now ~372pt, floating as a small island with
~128pt of dead space pooled above and below it. Meanwhile the caption (109pt of
24pt type) had become nearly as heavy as the photo band it describes.

Both siblings on this flow already solve this: `PointsBody` and `RankBody` use
`SizedBox.expand` + `Spacer()`s to *fill* the body area rather than centre a
min-height column in it. The rewards card adopts the same structure.

```
SizedBox.expand
└─ Column(crossAxisAlignment: stretch)
   ├─ _TitleBlock            title (big2) + spacingMedium + subtitle (pBig/text3rd)
   ├─ Spacer(flex: 3)
   ├─ RewardsCarousel        138.67pt  ← the photo band
   ├─ (spacingBig)
   ├─ RewardFeaturedCaption   95pt     ← reserved, constant
   └─ Spacer(flex: 4)
```

`Spacer` cannot share a `Column(spacing:)` without gapping around itself, so the
outer `Column` carries no `spacing:` and the carousel→caption gap is an explicit
`spacingBig` on a nested `Column(spacing: DesignConstants.spacingBig)` holding
those two.

The 3:4 Spacer split biases the photo band slightly above true centre — the
standard optical-centre correction — and gives the caption room to breathe
without pushing it into the CTA.

Resulting mass order: photo band 139 > caption 95 > title 71. The photo, which
is what the card is about, is the largest element again. Before this change the
caption (109) was within 30pt of the photo band (139).

Entrance motion is unchanged: `StaggeredReveal` on title (0), subtitle
(`revealStagger`), carousel (`revealStagger + revealDuration`, `offset: 0`).

---

## 6. Behaviour: what the carousel does differently

| Behaviour | Verdict |
|---|---|
| Giftbox intro (`_GiftboxIntro`, 520 + 600 + 540ms, 14-star burst) | **Keep, unchanged.** It is the card's entrance and the `PostClassController` skip contract (`_skipToFinal` → `markDone`) hangs off it. It plays in every state, including ≥90%: the gift is the *category* (rewards exist, here is where you stand), and the card is only ever reached when the member is within 10% of one. |
| 3D cover-flow transform (`_minScale` 0.56, `_maxTilt` 0.6, `setEntry(3,2,0.0015)`) | **Keep, unchanged.** |
| `_featuredSize` 208 / `_featuredAspect` 1.5 | **Keep, unchanged.** See §2 for why 208 cannot go up. |
| Auto-advance (5s idle, 450ms `easeInOutCubic`, infinite `_initialPageBase` wrap) | **Keep, unchanged, in every state.** In the ≥90% state the carousel does walk off the target reward after 5s. That is correct: the catalog *is* the aspiration and the member can swipe back; the title, the derived `featuredIndex` and the caption have already delivered the message on the first beat. A per-state advance delay was considered and rejected as a special case with no payoff. |
| `featuredIndex` | **Changes** — see below. |
| Slide ordering | **Preserved** — see below. |
| **One-item catalog** | **Changes** — see below. This is a live bug. |

### `featuredIndex` — derived, not `mockRewardsStats.featuredIndex`

Today `RewardsCardScreen` passes `mockRewardsStats.featuredIndex` (a hardcoded
`1`) into the **live** catalog, so the card opens on whatever the gym's second
reward happens to be. That is a demo value leaking into live data.

Derived instead:

* ≥1 affordable → **the most expensive affordable one** — the biggest thing the
  member can have right now, which is the strongest opening beat.
* 0 affordable → **index 0, the cheapest** — the reward the ≥90% claim is about.
  Opening anywhere else would be irrelevant at best and cruel at worst.
* Unknown → **index 0**.

`MockRewardsStats.featuredIndex` then has zero readers. Per the *Always delete
dead code* rule, remove the field from `MockRewardsStats` and from the
`mockRewardsStats` const. Verified safe: `grep -rn "mockRewardsStats\|
MockRewardsStats" lib/ test/ tools/` returns only `rewards_card_screen.dart`,
`mock_stats.dart` and `rewards_carousel_test.dart`. The capture harness's
`AppScreen.rewards` renders `PointsStoreScreen`, **not** this card, so
`mock_stats.dart`'s capture coupling (`StreakBody` / `WinsBody`) is untouched.

### Ordering — preserved, and the reason is arithmetic

`FastApiBackend/src/rewards/sql/list_rewards.sql` ends `ORDER BY point_cost ASC`,
and `MemberRewardsRepository.listCatalog` preserves it. The catalog therefore
arrives **cheapest first**, which already *is* "most attainable first".

Sorting by `affordable desc, cost asc` is **provably identical** to `cost asc`
when costs are ascending: `affordable ⟺ cost <= balance`, so every affordable
item is already a prefix of the list. A reorder would be a no-op that adds code
and a second source of truth for an order the backend already owns. It would
also make the celebration show the gym's catalog in a different sequence from
the store, which shows the same list.

The card-level maths (cheapest, any-affordable) still uses `reduce(math.min)`
rather than trusting `[0]`, so a future backend ordering change cannot silently
break the gate.

### One reward in the catalog — a live bug, fixed here

Traced through the current code: `_count = 1`, so
`_page = 10000 - (10000 % 1) + 0 = 10000`, `_index = 0`. `PageView.builder` has
no `itemCount`, so it is infinite, and `itemBuilder`'s `page % 1` is always `0`.
The result is that every 5 seconds the card animates a 450ms horizontal slide
from a photo to **the identical photo**, while the caption's `AnimatedSwitcher`
(keyed on an unchanging `featuredIndex`) does not cross-fade and `_PulsePoints`
(keyed `'pts-0'`) does not re-fire. The member sees an unexplained drift.

Fix, in `RewardsBody`:

* `_scheduleNext()` returns immediately when `_count <= 1` — no timer.
* `RewardsCarousel` takes `physics:` and gets
  `const NeverScrollableScrollPhysics()` when `items.length <= 1`, so there is no
  swipe to nowhere either. (It keeps `BouncingScrollPhysics` otherwise.)

The single slide renders centred at full featured size with its ring and tags;
the caption is static. Everything else — intro, reveals, CTA — is unchanged.

**Also fix the latent zero-item crash:** `_initialPageBase % _count` throws on
`_count == 0`. `RewardsBody` is a public widget taking `slides`, so add
`assert(slides.isNotEmpty)` and an early `if (widget.slides.isEmpty) return
const SizedBox.shrink();` guard in `build`. Today's screen can never pass an
empty list (`_loadSlides` falls back to the bundled three), but the widget must
not be a landmine.

---

## 7. The skip rule

### 7.1 The predicate

```dart
/// Whether the post-class rewards card is worth showing: the member can redeem
/// SOMETHING, or is within 10% of the cheapest reward.
///
/// `balance >= cheapest` implies `balance * 10 >= cheapest * 9`, so the
/// "anything affordable" clause collapses into the 90% clause — one comparison,
/// not two. Integer maths on purpose: `0.9 * cost` drifts at the boundary
/// (900 / 1000 must be TRUE).
bool rewardsCardWorthShowing({
  required int? balance,
  required Iterable<int> costs,
}) {
  if (costs.isEmpty) return false;   // nothing to carousel
  if (balance == null) return true;  // unknown -> show (the default-to-show law)
  final cheapest = costs.reduce(math.min);
  if (cheapest <= 0) return true;    // a 0-cost reward is always redeemable
  return balance * 10 >= cheapest * 9;
}
```

### 7.2 How it composes with the existing `hasRewards` gate

`celebration_flow.dart` stays the one place that decides card order. The new
input sits alongside `hasRewards`, in the same shape:

```dart
List<String> celebrationCardRoutes({
  required bool hasRewards,
  required bool rewardsWorthShowing,   // NEW
  required bool rankEnabled,
  required bool hasRank,
}) => <String>[
      AppRoutes.postClassStreak,
      AppRoutes.postClassPoints,
      if (hasRewards && rewardsWorthShowing) AppRoutes.postClassRewards,
      if (rankEnabled && hasRank) AppRoutes.postClassRank,
    ];
```

The two gates are independent and both must pass:
`gymHasRewards` (does the gym run rewards at all — a cached identity flag,
synchronous, already correct) **AND** `rewardsWorthShowing` (can this member
reach one). `gymHasRewards == false` short-circuits and the catalog is never
fetched.

`nextCelebrationCard` gains the balance, mirroring how it already reads
`selectedMember` for the gym flags:

```dart
String? nextCelebrationCard({
  required String current,
  required bool hasRank,
  required int? pointsBalance,          // NEW — from the caller's BlocBuilder
}) {
  final costs = CelebrationRewardsGate.instance.costs;
  final routes = celebrationCardRoutes(
    hasRewards: selectedMember.gymHasRewards,
    // Undecided (still in flight, or the prime failed) -> SHOW.
    rewardsWorthShowing: costs == null
        ? true
        : rewardsCardWorthShowing(balance: pointsBalance, costs: costs),
    rankEnabled: selectedMember.gymRankEnabled,
    hasRank: hasRank,
  );
  final index = routes.indexOf(current);
  if (index < 0 || index + 1 >= routes.length) return null;
  return routes[index + 1];
}
```

All four screens already hold `state.profile` in the `BlocBuilder` that wraps
this call, so each call site gains one line:
`pointsBalance: state.profile?.retention.pointsBalance`.

### 7.3 Where the catalog comes from — `CelebrationRewardsGate`

New file: `lib/features/stats/data/celebration_rewards_gate.dart`.

```dart
/// The reward catalog the post-class flow decides on, fetched ONCE when the
/// celebration is pushed and reused by the card itself.
class CelebrationRewardsGate extends ChangeNotifier {
  CelebrationRewardsGate._();
  static final CelebrationRewardsGate instance = CelebrationRewardsGate._();

  List<RewardItem>? _catalog;

  /// The catalog, or null while the prime is in flight / after it failed.
  List<RewardItem>? get catalog => _catalog;

  /// The point costs, or null when undecided.
  Iterable<int>? get costs => _catalog?.map((r) => r.pointCost);

  void reset() { _catalog = null; notifyListeners(); }

  /// Fire-and-forget. Never throws: a failure leaves the gate undecided, which
  /// the flow reads as "show" (see nextCelebrationCard).
  Future<void> prime({MemberRewardsRepository? repository}) async { … }
}
```

`prime` reads `selectedMember.gymId` / `.memberId` (returns silently if either
is null), calls `listCatalog`, assigns `_catalog`, and `notifyListeners()`. Any
throw is logged with `log(...)` and swallowed.

It deliberately holds only the **catalog**, not a decided boolean. The balance
lives on the shared `MemberProfileBloc` and is read fresh at decision time, so
the gate has exactly one responsibility and can never hold a stale balance.

**Primed at the moment the flow is pushed** — inside `CelebrationDetector`, at
both push sites, immediately before `navigator.pushNamed(postClassStreak, …)`:

```dart
CelebrationRewardsGate.instance.reset();
unawaited(CelebrationRewardsGate.instance.prime());
navigator?.pushNamed(AppRoutes.postClassStreak, arguments: …);
```

`reset()` first, so a second celebration in the same session never decides on
the previous one's catalog. `CelebrationDetector` takes the gate as a
constructor parameter defaulting to the singleton — the same test seam it
already gives `historyRepository` and `watermark`.

### 7.4 What happens when the catalog has not loaded yet

**It defaults to SHOW, and the card can never bounce.** Three properties make
that safe, and they must all hold:

1. **The decision is read at the POINTS card's build**, because the points card
   is the one whose CTA pushes the rewards card. The prime starts one full card
   earlier, at the push of the streak card. The member must clear the streak
   card's ~3s reveal gate and tap Continue before the answer is needed, against
   a single `GET` that started before the first frame of the flow. In practice
   it is always resolved.
2. **`RewardsCardScreen` never self-skips.** Once pushed, it renders — always.
   This is the no-flicker invariant, and it is the reason "undecided → show" is
   harmless: the worst case is a card the member could have been spared, not a
   card that appears and vanishes. (The asymmetry with `RankScreen`, which *does*
   self-skip, is correct: `RankScreen` can render literally nothing when
   `buildRankStats() == null`, so it needs a deep-link backstop. The rewards
   card can always render the catalog, or the bundled fallback.)
3. **A late resolution still lands.** `CelebrationRewardsGate` is a
   `ChangeNotifier`, and `PointsScreen` wraps its `nextCelebrationCard` call in a
   `ListenableBuilder(listenable: CelebrationRewardsGate.instance, …)` so its CTA
   label and destination re-derive if the catalog arrives after first build. The
   other three screens do **not** need it — the streak card's successor is always
   points, the rewards card's is rank-or-null, the rank card's is always null —
   and adding it there would be noise. Put a one-line comment on the points
   screen saying exactly that.

There is no race at tap time: Flutter is single-threaded, so the handler reads
whatever the gate currently says and pushes accordingly. Either answer is
self-consistent, because of property 2.

Also true because the gate is a real catalog cache, not just a flag:

* **The card reuses it.** `RewardsCardScreen._loadSlides()` returns
  `CelebrationRewardsGate.instance.catalog` mapped to slides when it is
  non-null, and only calls `listCatalog` when it is null. In the normal flow
  that removes both a second round trip **and** the card's
  `RewardsLoadStatus(null)` spinner.
* **PR-3's after-class push** (a deep link straight to
  `AppRoutes.postClassRewards`) finds an unprimed gate, fetches for itself, and
  behaves exactly as today. That is right: an explicit deep link to the rewards
  card should show the rewards card.
* **The dev preview** (`CelebrationDetector.fireNow`, the identity sheet's
  Developer row) primes identically, so it previews the real gate.

### 7.5 When the fetch fails entirely

Undecided → the card shows → the card's own fetch also fails → it falls back to
`mockRewardsStats.items` (today's behaviour). Those are **demo costs** (800 /
2,200 / 3,500). Rendering `120 / 2,200 points` against a demo catalog would be a
lie, so:

`RewardSlide` gains `final bool isLive;` — `true` on `fromRewardItem` /
`fromReward`, `false` on `fromMock`. **A non-live slide always resolves to the
`unknown` state**, whatever the balance is. One code path, two triggers (null
balance, or non-live slide), and the unknown state is today's shipped look, so
the offline card degrades to something already proven.

---

## 8. View-model

New file `lib/features/stats/data/rewards_card_view.dart` — one pure function
that owns every state decision above, so no widget re-derives anything.

```dart
enum RewardAffordance { redeemable, locked, unknown }

class RewardsCardSlide {
  final RewardSlide slide;
  final RewardAffordance affordance;
  final double progress;        // 0..1; 1.0 for redeemable and unknown
  final String valueLabel;      // '800 pts' | '120 / 2,200 points'
}

class RewardsCardView {
  final String title;
  final String subtitle;
  final int featuredIndex;
  final List<RewardsCardSlide> slides;
}

RewardsCardView buildRewardsCardView({
  required List<RewardSlide> slides,
  required int? pointsBalance,
});
```

`progress` for a locked slide is `(balance / cost).clamp(0.0, 1.0)`; a
`cost <= 0` slide is `redeemable`.

**Move `reward_slide.dart` from `presentation/widgets/rewards/` to
`features/stats/data/`.** It is a pure data class with no `build` method, and
`rewards_card_view.dart` (in `data/`) must not import from `presentation/`.
Three imports and one test import update with it.

---

## 9. File-organisation

`rewards_body.dart` is 464 lines with five classes — already far past the ~150
line / one-public-widget rule, and this change adds to it. Split it while it is
open:

| File | Contents | ~lines |
|---|---|---|
| `rewards_body.dart` | `RewardsBody` (intro gate, advance timer, page state) | 110 |
| `rewards_card_layout.dart` | `RewardsCardLayout` (was `_CarouselLayout`; now the `SizedBox.expand` + Spacer structure of §5) | 80 |
| `rewards_giftbox_intro.dart` | `GiftboxIntro` + `_BurstStarSeed` (moved verbatim) | 150 |
| `reward_featured_caption.dart` | `RewardFeaturedCaption` + `_PulsePoints` | 110 |
| `rewards_carousel.dart` | `RewardsCarousel` + `_RewardSlideImage` + `_RewardRingPainter` | 150 |

`_formatPoints` in `rewards_body.dart` is deleted; call sites use
`formatRewardPoints` from `reward_card.dart` (Finding F-1).

---

## 10. Copy strings, complete list

| String | Where |
|---|---|
| `Rewards you can get` | title, ≥1 affordable and unknown |
| `Almost there` | title, 0 affordable / ≥90% |
| `{n} reward ready to redeem` | subtitle, exactly one affordable |
| `{n} rewards ready to redeem` | subtitle, two or more affordable |
| `{gap} points to go` | subtitle, 0 affordable / ≥90% |
| `Swipe to view rewards` | subtitle, unknown (unchanged) |
| `Ready` | `RewardReadyTag` on the slide |
| `Ready to redeem` | caption state line, redeemable |
| `{cost} pts` | caption value, redeemable and unknown (unchanged form) |
| `{balance} / {cost} points` | caption value, locked |

All point numbers pass through `formatRewardPoints`.

---

## 11. Every state, wired

| # | Condition | Card shown? | Title / subtitle | Featured slide | Slides |
|---|---|---|---|---|---|
| 1 | `gymHasRewards == false` | **No** (existing gate) | — | — | — |
| 2 | Catalog empty | **No** (`costs.isEmpty`) | — | — | — |
| 3 | Everything affordable | Yes | `Rewards you can get` / `{n} rewards ready to redeem` | most expensive | all accent closed ring + Ready tag |
| 4 | Some affordable, some not | Yes | `Rewards you can get` / `{n} rewards…` | most expensive affordable | mixed |
| 5 | None affordable, ≥90% to cheapest | Yes | `Almost there` / `{gap} points to go` | cheapest (index 0) | all locked; featured ring ≥90% closed |
| 6 | None affordable, <90% | **No** | — | — | — |
| 7 | Balance null (profile loading / errored) | Yes (undecided → show) | `Rewards you can get` / `Swipe to view rewards` | index 0 | all unknown = today's look |
| 8 | Catalog fetch failed → bundled slides | Yes | as #7 | index 0 | all unknown (`isLive == false`) |
| 9 | Exactly one reward | per #3–#6 | per state | the one | no auto-advance, no swipe |
| 10 | Reward image fails to load | per state | per state | per state | `ColoredBox(card)` inside the frame; ring + tags unaffected |

---

## 12. Tokens used — complete list

Colours: `accent`, `text`, `text2nd`, `text3rd`, `primaryColor`, `divider`,
`card`, `backgroundColor`.
Type: `big2`, `pBig`, `h1`, `h2`, `h2Regular`, `pSmall`.
Spacing: `spacingSmall`, `spacingMedium`, `spacingBig`.
Radius: `radiusBig`, `radiusSmall`.
Strokes: `buttonBorderSize`, `dividerThickness`.
Icons: `iconSizeXs`, `iconSizeSm`, `iconWeight`, `Symbols.check_sharp`.
Timings: `CelebrationTimings.revealStagger`, `.revealDuration`.

`_k` file-scoped constants (permitted by the CLAUDE.md carve-out for per-screen
layout maths): `_kCaptionNameHeight = 31`, `_kCaptionValueHeight = 56`. The
existing `_kBoxEntrance` / `_kBoxHold` / `_kBoxBurst` / `_kBoxSize` /
`_kBurstStarCount` move with `GiftboxIntro`.

**No new `DesignConstants` token is added** (see OQ-1 for the one that would be
worth asking about).

---

## 13. Widgets reused, not rebuilt

| Reused | From | For |
|---|---|---|
| `RewardPriceTag` | `features/rewards/.../reward_card.dart` | the value tag on the slide, verbatim, at `RewardImageHero`'s exact position |
| `formatRewardPoints` | same file | every points number |
| `NextRankSection`'s `'$done / $target …'` form + `h2Regular`/`text2nd` | `features/profile/.../next_rank_section.dart` | the `x/y points` line |
| `_ProgressArcPainter`'s tokens and semantics | `features/profile/.../next_rank_badge.dart` | the ring (RRect variant, comment cites the original) |
| `ClassReservedTag`'s colour law + `Symbols.check_sharp` | `shared/widgets/class_reserved_tag.dart` | accent = state achieved |
| `RewardCard._kCardTitleHeight` reserved-slot idiom | `features/rewards/.../reward_card.dart` | reserved caption heights |
| `PointsBody` / `RankBody`'s `SizedBox.expand` + `Spacer` structure | `features/stats/.../points_body.dart`, `rank/rank_body.dart` | filling the body area |
| `StaggeredReveal`, `CelebrationTimings`, `PostClassController`, `PostClassScaffold`, `RewardsLoadStatus`, `MemberRewardsRepository` | unchanged | unchanged |

---

## 14. Files an implementer touches

**New**

1. `lib/features/stats/data/celebration_rewards_gate.dart`
2. `lib/features/stats/data/rewards_card_view.dart`
3. `lib/features/rewards/presentation/widgets/reward_card/reward_ready_tag.dart`
4. `lib/features/stats/presentation/widgets/rewards/rewards_card_layout.dart`
5. `lib/features/stats/presentation/widgets/rewards/rewards_giftbox_intro.dart`
6. `lib/features/stats/presentation/widgets/rewards/reward_featured_caption.dart`

**Moved**

7. `lib/features/stats/presentation/widgets/rewards/reward_slide.dart`
   → `lib/features/stats/data/reward_slide.dart` (+ `isLive`)

**Modified**

8. `lib/features/stats/data/celebration_flow.dart` — `rewardsWorthShowing` param,
   `pointsBalance` param, gate read
9. `lib/features/stats/data/celebration_detector.dart` — gate ctor seam +
   `reset()` / `prime()` before both pushes
10. `lib/features/stats/data/mock_stats.dart` — drop `MockRewardsStats.featuredIndex`
11. `lib/features/stats/presentation/screens/rewards_card_screen.dart` — read the
    primed catalog, build the view-model, pass it down
12. `lib/features/stats/presentation/screens/points_screen.dart` — `ListenableBuilder`
    on the gate + `pointsBalance:`
13. `lib/features/stats/presentation/screens/streak_screen.dart` — `pointsBalance:`
14. `rank_screen.dart` is **not** touched — verified: it never calls
    `nextCelebrationCard` (it hardcodes `ctaLabel: 'Continue'`; see Finding F-7)
15. `lib/features/stats/presentation/widgets/rewards/rewards_body.dart` — shrink to
    the state shell; one-item guards; zero-item assert
16. `lib/features/stats/presentation/widgets/rewards/rewards_carousel.dart` — ring
    painter, tags, `physics:` param

**Tests**

17. `test/features/stats/data/celebration_flow_test.dart` — new params + new cases
18. `test/features/stats/data/celebration_rewards_gate_test.dart` — **new**:
    the pure predicate. Cases: empty costs → false; null balance → true;
    `cheapest == 0` → true; `900/1000` → **true** (the boundary); `899/1000` →
    false; `1200/1000` → true; unordered costs still find the min.
19. `test/features/stats/data/rewards_card_view_test.dart` — **new**:
    `featuredIndex` derivation in all three modes; per-slide affordance,
    `progress` and `valueLabel`; title/subtitle per state; one-item catalog;
    non-live slides all `unknown`.
20. `test/features/stats/presentation/widgets/rewards/rewards_carousel_test.dart` —
    keep 3:2 / `radiusBig` / 208 / `BoxFit.cover` / `errorBuilder`; the border
    assertion moves from `BoxDecoration.border` to the painter; add closed-accent
    vs partial-`text` ring, and `RewardReadyTag` present only when redeemable.
21. `test/features/stats/presentation/celebration_last_card_test.dart` — add: with
    the gate primed on an unaffordable catalog, the points card's CTA goes
    straight to rank (and reads `Done` at a rank-off gym).
22. **New** one-item test: no auto-advance timer, `NeverScrollableScrollPhysics`.

**Docs (same change, per the living-document rule)**

23. `MobileApp/CLAUDE.md` — the *post-class celebration is composed, not
    hardcoded* section must state the second rewards gate (`gymHasRewards` **and**
    the ≥90% affordability gate), the `CelebrationRewardsGate` prime-at-push
    step, and the no-self-skip invariant.

**Verification:** `flutter analyze` clean, `flutter test` green, and a live run
of the celebration through the identity sheet's DEBUG "Post-class celebration"
row against a seeded member in each of states #3, #4, #5, #6 and #9.

---

## 15. Open questions

**OQ-1 — an `accentButtonText` token.** `RewardReadyTag` needs a foreground that
reads on a solid `accent` fill. `DesignConstants` has `primaryButtonText`
(`ThemeColor.color(primary, derivation: regularText, …)`) but no accent
equivalent. Every base slot already ships a `regular_text` derivation on the
wire, so this is a **one-line getter, no new slot and no wire change**:

```dart
static Color get accentButtonText => ThemeColor.color(
  CombatDenSlots.accent,
  derivation: ThemeDerivation.regularText,
  fallback: _fallbackBackground,
);
```

CLAUDE.md forbids adding tokens without explicit permission, so this spec ships
the interim: `DesignConstants.backgroundColor` as the on-accent foreground.
Contrast is symmetric, and accent-on-background is a pairing the app already
relies on everywhere (`ClassReservedTag`, the active nav item, timeframe pills),
so background-on-accent has the same ratio. **Ask before adding the getter.**

**OQ-2 — copy casing.** §4 sets sentence case (`Rewards you can get`). Today's
string is Title Case. One word, either way — confirm.

**OQ-3 — a "one more class" clause.** In the ≥90% state, `CelebrationData`
carries `pointsWorth` (what the class just attended was worth), so the subtitle
*could* read `One more class` when `gap <= pointsWorth`. Deliberately **not**
specified for v1: `pointsWorth` is `0` on `CelebrationData.empty()` and on the
PR-3 deep-link, and the next class may be worth less than the last, so it is a
promise the app cannot keep. Worth revisiting once the push payload is real.

**OQ-4 — move the gate server-side.** The whole client prefetch disappears if
`MemberPortalIdentity` carried a `cheapest_reward_cost` beside `gym_has_rewards`
(which is already derived from the same predicate as the rewards list). The
gate would then be as synchronous as `gymHasRewards`, and no card would ever be
"undecided". That is a backend change, out of this spec's scope; raise it if
the flow ever needs a second async gate, because a second one would not be
worth building client-side.

---

## 16. Findings outside this scope (flagged, not fixed)

**F-1 — the points formatter exists four times.** Identical implementations in
`reward_card.dart` (`formatRewardPoints`, the only public one),
`rewards_body.dart` (`_formatPoints`), `points_headline.dart` (`_formatPoints`)
and `points_body.dart` (`_formatThousands`). This spec deletes the
`rewards_body.dart` copy (it is inside the scope being rewritten). The other two
should collapse onto `formatRewardPoints` — or it should be promoted to a
shared helper — in a separate change.

**F-2 — `RewardSlide.fromReward` is dead.** Zero call sites
(`grep -rn "fromReward\b" lib/ test/ tools/`). It is the only thing importing
`features/rewards/data/reward.dart` into the celebration, and `Reward` itself is
kept alive only by the dormant, capture-coupled `features/gym/data/gym_detail.dart`.
Per *Always delete dead code* the factory should go; not done here because the
dormant-batch removal is the founder's pending decision.

**F-3 — a stale doc comment on `NextRankBadge`.** Its class doc says "Circular
belt icon with an **orange** progress arc", but the code passes
`color: DesignConstants.text` (`next_rank_badge.dart:47`). The comment is wrong;
the code is what this spec mirrors.

**F-4 — the reward-image placeholder is a dead grey box.** Both
`_RewardSlideImage` and the store's `RewardImageHero` fall back to a bare
`ColoredBox(color: DesignConstants.card)`. A shared `RewardImagePlaceholder`
(`Symbols.card_giftcard_sharp` — the app's own rewards glyph, from the bottom
nav — at `iconSizeXl` in `text3rd` over the `card` fill) would fix both at once.
Not done here: touching only the celebration copy would break the "one uploaded
photo is framed identically on both surfaces" law, and the store is explicitly
out of scope.

**F-5 — a stale comment in `mock_stats.dart`.** Line 152 says the card shows the
gym's live rewards from `GET /gyms/{gymId}` — that is the retired VideoService
path. It is the member portal now
(`GET /api/v1/member/gyms/{gid}/members/{mid}/rewards`). One-line fix, worth
taking with this change since the block is being edited anyway.

**F-7 — the rank card's CTA says "Continue" but ends the flow.**
`rank_screen.dart:69` hardcodes `ctaLabel: 'Continue'` while `onCtaPressed`
is `_toHome`. The rank card is always the LAST card, and
`celebrationCtaLabel`'s stated law is that the last card reads "Done". It is the
one celebration screen that does not route its label through
`celebrationCtaLabel(nextCelebrationCard(...))`. A member is told there is
another card and then dropped home. One-line fix (`ctaLabel: 'Done'`, or better,
route it through `celebrationCtaLabel(next)` like its three siblings) — left
alone here because it is a different card.

**F-6 — the caption's `AnimatedSwitcher` had no reserved height.** Pre-existing:
`_CarouselLayout`'s caption `Column` is `MainAxisSize.min` inside a
`Center`-ed min-height column, so any per-slide height difference (a two-line
reward name today) shifts the entire stack on advance. §3's reserved heights fix
it as a side effect; noting it so the reserved-height requirement is not
mistaken for gold-plating.
