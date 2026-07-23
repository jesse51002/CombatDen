# Growth page — design spec

Implementation spec for the six-tab, envelope-driven Growth page. Every value here
is either an existing `DesignConstants` token, a formula over one, or a measured
number with the measurement shown. Where a token does not exist it is listed in
**Proposed new tokens** — nowhere else.

Sources read: `CRM/PRODUCT.md`, `CRM/DESIGN.md`, `CRM/CLAUDE.md`,
`lib/core/constants/design_constants.dart`, the current `features/growth/` tree,
`features/home/.../total_members_hero/`, `lib/shared/widgets/`,
`features/memberships/presentation/screens/memberships_screen.dart`,
`PlanServer/plans/growth-page-live-metrics/{canvas.mdx,plan.mdx}`.

Design register: **product**. Color strategy: **Restrained** — one sapphire voice,
status hues functional only. The One Light Rule and the De-Card Rule hold on every
tab; nothing on this page is boxed in a card.

---

## 1. Page chrome

### 1.1 Shell

`AppShell(activeRoute: AppRoutes.growth)` wrapping a `Column`, structurally
identical to `memberships_screen.dart` so Growth reads as its sibling:

```
Column(spacing: spacingBig)
  Padding(top: paddingBig, left/right: screenHorizontalPadding)
    Column(spacing: spacingBig)
      ViewSwitcher(labels: 6 tabs)
      MetaRow                      // freshness + filters  (replaces Gym's title + Add button)
  Expanded(child: IndexedStack(index: tabIndex, children: 6 tab bodies))
```

Each tab body is its own `SingleChildScrollView` with
`padding: EdgeInsets.symmetric(horizontal: screenHorizontalPadding, vertical: paddingBig)`.
`IndexedStack` keeps each tab's scroll offset and filter state alive — one backend
read serves all six tabs, so switching never refetches.

### 1.2 Tab bar

`ViewSwitcher` (shared, unchanged) with
`['Overview', 'Revenue', 'Members', 'Retention', 'Trial', 'Attendance']`.
Default index 0 (Overview). Money first (Revenue, Members), then the retention
arc (Retention, Trial), with operational Attendance last. Tab switch = local
`setState` + `syncBrowserUrl(kGrowthTabRoutes[i])`, exactly as
`_MembershipsBodyState._onTabSelected` does. The tab labels, `_categories`,
`kGrowthTabRoutes`, and the `GrowthPageBody` `IndexedStack` children all list in
this one order so they cannot drift; `main.dart` deep-links resolve by
`kGrowthTabRoutes.indexOf(path)`, so the route CONSTANTS are unchanged — only
their order in the list moved.

- Desktop label style: the `ViewSwitcher` default (`pBig`, 16).
- Below `navMobileBreakpoint` (768): pass `textStyle: DesignConstants.h3` (13).
  Six tabs × `pBig` overflows below ~790px; `h3` fits to ~430px.

**No page/tab title below the bar.** The Gym screen repeats its tab name in `big2`
because it pairs with an Add button; Growth has no primary action and the tab bar
already names the view. Repeating it is restated-heading noise.

### 1.3 Meta row

One row, directly under the tab bar, holding everything that scopes the tab below
it (dataviz rule: one filter row above everything it scopes — never a per-chart
filter).

```
IntrinsicWrap(spacing: spacingLarge, runSpacing: spacingMedium)
  FreshnessStamp                  // left
  Spacer-equivalent
  FilterPills(range)              // right: All | Year | 6M | 3M
  FilterPills(class)              // Attendance only, second run
```

Use `IntrinsicWrap` (shared) so it wraps to two lines below 768 instead of
overflowing. On desktop this is a `Row` with the stamp `Expanded` and the pills
trailing.

**Freshness stamp** — `pSmall` in `text3rd`:
- `computed_at` within 24h → `Updated hourly · as of 2:00 PM`
  (`DateFormat.jm().format(computedAt.toLocal())`).
- older → `Updated hourly · as of Jul 18, 2:00 PM` (`DateFormat.MMMd().add_jm()`).
- refetch in flight → the same text at 40% opacity with an
  `AppSpinner(size: iconSizeTiny)` leading it, `spacingSmall` gap.

**Range pill** — the shared `FilterPills` (single-select), labels
`['All', 'Year', '6M', '3M']`, default `All`. It filters **client-side** and only
touches `line` and `bars` metrics: it trims each series' `points` to those whose
`date` is within the window of the newest point in that series. `kpi_group`,
`hero_split`, `breakdown`, `donut_pair`, `heatmap` and `member_list` are
current-state snapshots and are untouched. So the user is never misled about what
the pill did, **every metric section carries its own window as a subtitle** (§1.5).

If a tab contains no `line`/`bars` metric, the range pill is not rendered.

**Class chips** — Attendance only. A second `FilterPills` run, labels
`['All classes', ...classNames]`, default index 0. Class names are the union of
`by_class` keys across the tab's metrics, in wire order. Selecting a class swaps
every metric that carries `by_class` onto that key's series/grid; metrics without
`by_class` render unchanged and keep their `All classes` subtitle.

### 1.4 Section rhythm and layout grid

Each metric renders as a **de-carded section**:

```
Column(crossAxisAlignment: start, spacing: spacingLarge)   // title block -> body
  Row                                                       // title block
    Column(spacing: spacingTiny)
      Text(metric.name,   style: h2)
      Text(windowLabel,   style: pSmall, color: text3rd)    // e.g. "Last 30 days"
    Spacer()
    Legend                                                  // only when >= 2 series
  <renderer body>
```

- Title `h2` (16/600) — DESIGN.md's "Title: section titles". The current Growth
  screen uses `h1` (24) for section titles; with 6–10 sections per tab that is too
  loud and steals from the page's one hero. Changed to `h2`.
- Sections are separated by `Hairline()` inside the tab's
  `Column(spacing: spacingBig)` → 32 / rule / 32. This is the current Growth
  screen's rhythm and DESIGN.md's De-Card Rule.
- Two half-width sections in one row are separated by `Hairline(vertical: true)`
  inside an `IntrinsicHeight` row with `spacing: spacingBig` — the same
  construction as `KpiStrip`. No horizontal hairline between them.

**Spans.** The tab body is a single column of rows. Every metric has a span of
`full` or `half`, taken from a client-side registry keyed by metric `key`, with a
per-type default. Two consecutive `half` metrics pair into one `IntrinsicHeight`
row; a `half` with no `half` neighbour renders `full`.

| type | default span |
|---|---|
| `kpi_group`, `hero_split`, `line`, `donut_pair`, `heatmap`, `member_list` | full |
| `bars` | full |
| `breakdown` | half |

Registry overrides (the only ones needed for the 28-metric catalog):
`members_by_plan` → full, `revenue_by_plan` → full, `promotions_trend` → half,
`redemptions_trend` → half, `cohort_retention` → half.

### 1.5 Window labels

Each section's subtitle is its own measurement window. The envelope has no
`window_label` field, so it comes from a **client-side registry keyed by metric
`key`** (the same registry that supplies KPI icons and span overrides), defaulting
to `''` (no subtitle) for an unknown key. See Open Questions for the alternative.

Values used: `Current` · `Last 30 days` · `Last 90 days` · `This week` ·
`This month vs last` · `Monthly, all-time` · `Weekly, all-time` ·
`Trailing 12-month average`.

---

## 2. Chart color system

The CRM has one accent and a reserved status trio; it has **no categorical chart
palette**. Rather than invent one, the system below assigns color by *job*, which
is what the data actually needs — of the 28 catalog metrics exactly one carries
three peer series.

Every pair below was measured with the dataviz validator
(OKLab ΔE ×100; Machado–Oliveira–Fernandes CVD at severity 1.0). Numbers are quoted
so they can be re-checked, not trusted.

### 2.1 The four roles

**A. Series ramp (ordinal) — the default for every multi-series `line` / `bars`.**
One hue, two lightness steps. Order is fixed and follows the entity, never its rank
or size.

| slot | token | role |
|---|---|---|
| S1 | `primaryColor` | the series that matters (the outcome, the achieved value) |
| S2 | `darkPrimary` | the companion (the upstream/reference/remainder) |

Validated as an **ordinal ramp**: light `#274777→#2A67BD` and dark
`#36527E→#3E7CD6` both **PASS** all four ordinal checks (monotone lightness,
ΔL ≥ 0.06, light-end ≥ 2:1 on surface, single hue).

This matches the app's existing semantics — `TotalMembersArc` already paints
active in `primaryColor` and inactive in `darkPrimary`.

Assignment rule per metric: S1 goes to the **downstream / smaller / "did it
happen"** series, S2 to the upstream reference. So Check-ins = S1, Sign-ups = S2;
Clicked = S1, Served = S2; Converted = S1, Started = S2. The bright accent lands on
the number the owner is trying to move.

**B. Residual slot — `text3rd`.** Reserved for (a) a segment/series that is
explicitly an "Other"/residual bucket, (b) a "not yet / pending" quantity, and
(c) the benchmark half of a `donut_pair`. Never given to a named peer series.
Measured against the ramp: `text3rd`↔`darkPrimary` ΔE 25.4 light / 20.5 dark
(normal), CVD 24.0 / 19.4 — comfortably separated.

**C. Tone palette (status, reserved).** `goodGreen` / `okYellow` / `badRed`, used
only where the color *means* good / at-risk / bad, always with a text label and
(on the KPI delta) a direction arrow, so meaning is never color-alone.

> **Hard constraint discovered.** `goodGreen`↔`badRed` collapse under
> deuteranopia: ΔE **3.4** light, **1.6** dark (floor is 6, target 8). Green and
> red may therefore **never** be the sole channel distinguishing two adjacent
> marks. Where a metric is a good/bad pair (`members_gained_lost`), the `bars`
> renderer uses its **diverging** mode — good above the zero baseline, bad below —
> so position carries identity and color is redundant reinforcement. See §4.4.

**D. Density ramp (sequential, `heatmap` only).** `primaryColor` alpha-blended
over `backgroundColor` at **25 / 50 / 75 / 100%**, plus a zero step.

| step | light | dark |
|---|---|---|
| 0 (no data) | `backgroundAlt` + 1px `line` outline | `backgroundAlt` + 1px `line` outline |
| 1 (25%) | `#C1D2E9` | `#1E304A` |
| 2 (50%) | `#8EAEDA` | `#294978` |
| 3 (75%) | `#5C8ACC` | `#3462A7` |
| 4 (100%) | `primaryColor` | `primaryColor` |

Expressed in code as
`Color.alphaBlend(DesignConstants.primaryColor.withValues(alpha: a), DesignConstants.backgroundColor)`
— no new color tokens. Lightness is monotone with ΔL ≥ 0.06 at every step in both
modes (validated). The lightest step sits at 1.5:1 against the ground, which is why
**every cell carries a 1px `line` outline** — that is the cell boundary, not
decoration.

**E. Data-owned color.** `rank_distribution` bars take each rank's own belt color
when the wire supplies one; absent that, `primaryColor` (see Open Questions).

### 2.2 Past the palette's length

- `line` / `bars`: at most **three** series are drawn — S1, S2, residual. A fourth
  and beyond are summed into a single `Other` series painted `text3rd`; if the wire
  already contains an `Other`, they merge into it. Never generate a hue, never cycle.
- `breakdown`: at most **eight** items. Beyond that, items 8..n sum into `Other`
  (`text3rd`), appended last.
- `hero_split`: segments beyond the third take `text3rd`; four or more untoned
  segments is a data-shape problem, not a color problem — render and log.

### 2.3 Measured deviations (both mitigated, both documented)

1. `primaryColor`↔`darkPrimary`, **light** mode: normal-vision ΔE **13.6** vs the
   15 floor (dark passes at 16.9). Mitigation, mandatory wherever the two are
   adjacent: a `spacingSmall` (4px) surface gap between touching marks, an
   always-present legend carrying the value beside each swatch, and a direct end
   label on `line`.
2. `primaryColor`↔`text3rd`, **dark** mode: normal-vision ΔE **13.7** (light
   passes at ≥17.7). Same mitigation. Slot order is fixed as S1→S2→residual, so the
   two weak pairs are never both adjacent in the same theme.

There is no third non-status, non-gray hue in `DesignConstants`; clearing both
floors requires one new token pair, offered in **Proposed new tokens** as optional.

### 2.4 Chart text and chrome

- **Text never wears a series color.** Axis ticks, values, legends, direct labels
  and captions use `text` / `text2nd` / `text3rd`. Identity comes from the colored
  swatch *beside* the text. The one exception is a label set inside a colored fill
  (a heat cell), which uses `DesignConstants.onFill(fill)`.
- Gridlines and baselines: 1px (`dividerThickness`) in `line`, **solid**, drawn
  behind the marks. Never dashed.
- Axis tick labels: `pSmall` in `text3rd`.
- Legend entry: the shared `SubgroupLegendDot` (`legendDotSize` 16 swatch +
  `h2Regular` label). For an in-chart legend in a title row use `pSmall` labels and
  render the swatch as a 16×16 dot; spacing `spacingLarge` between entries.

---

## 3. Chart geometry primitives

Shared by the `line`, `bars`, `breakdown` and `heatmap` painters.

**Plot height.** `heroChartHeight` (200) for the plot area of every full- and
half-width `line`/`bars` chart. The section's `Column` grows to include the x-axis
band beneath it — the outer container is **never** height-capped, so axis labels can
never be clipped into a nested scroll.

**Y axis.** Three ticks: `max`, `max/2`, `0`, laid out as a `Column` with
`mainAxisAlignment: spaceBetween` **to the left of the plot**, `spacingMedium` gap.
(The current `_MembersTrendChart` puts them on the right with a fake `'140 -'`
suffix; both change — left is the reading-order convention, and the suffix is
replaced by real gridlines.) `max` is the "nice" ceiling of the data max: round up
to 1 / 2 / 2.5 / 5 × 10^k. A gridline is drawn at each tick.

Tick formatting by `unit`:
- `count` → exact below 10,000 (`NumberFormat.decimalPattern`), else `12.4k` / `1.2M`.
- `cents` → `formatMinorUnits(v, decimalDigits: 0)` below $1,000, else `$9.1k` / `$1.2M`.
- `percent` → `41%` (values arrive 0–100).

**X axis.** Labels from each point's `date`, by `granularity`:
`month` → `DateFormat("MMM''yy")` → `Feb'25`; `week`/`day` → `DateFormat.MMMd()` →
`Jun 2`; the newest bucket of a weekly series renders `This wk`.
Decimation: `maxLabels = (plotWidth / 56).floor().clamp(2, points.length)`, sampled
evenly, **always including the first and last**. `spacingMedium` between plot and
label row.

**Bar geometry.**
```
n     = bucket count, s = drawn series (1..3)
slot  = plotWidth / n
barW  = grouped ? ((slot - spacingMedium) - spacingSmall * (s - 1)) / s
                : (slot - spacingMedium)
barW  = barW.clamp(1, chartBarMaxWidth)         // 24
topR  = min(radiusSmall, barW / 2)              // 8, auto-clamped on thin bars
```
Bars grow from a single baseline, `topR` on the two **data-end** corners only,
square at the baseline. Adjacent bars in a group are separated by a `spacingSmall`
surface gap; stacked segments by a `spacingSmall` gap in `backgroundColor`. Never
stroke a bar to separate it.

**Line geometry.** The existing Catmull-Rom spline in `_MembersTrendLinePainter`,
promoted to `lib/shared/widgets/charts/`, with:
- stroke `chartStroke` (2, was a hardcoded 3), round cap + join;
- single-series only: an area fill of the series color at 10% alpha, from the line
  to the baseline;
- an end marker at each series' last point: filled circle r = 4 in the series
  color, with a 2px ring in `backgroundColor`;
- a direct end label (`pSmallSemibold` in `text`) beside each end marker; if two
  end labels would sit within `spacingLarge` of each other, drop both and rely on
  the legend.

---

## 4. The eight renderers

Every renderer is a widget under
`lib/features/growth/presentation/widgets/renderers/`, selected by
`GrowthMetricView`'s switch on `type`. Painters that are generic
(`SplinePainter`, `TimeBarsPainter`, `BreakdownBarsPainter`, `HeatGridPainter`,
`SplitArcPainter`) live in `lib/shared/widgets/charts/`.

### 4.1 `kpi_group`

**Anatomy.** `KpiStrip` (existing) → N × `KpiTile` separated by
`Hairline(vertical: true)`, inside `IntrinsicHeight`, `spacing: spacingBig`.

`KpiTile` (existing structure, `Column(spacing: spacingMedium)`):
| part | token |
|---|---|
| label | `h2`, `text` |
| icon | `Symbols.*_sharp`, `iconSizeMedium`, `text2nd`, `weight: iconWeight` |
| value | `big2Light` (32/w300), `text` |
| delta badge | see below |
| comparison caption | `p`, `text2nd` |

**Value formatting** by `tile.unit`: `count` → `NumberFormat.decimalPattern`;
`cents` → `formatMinorUnits(v, decimalDigits: 0)`; `percent` → `'41%'`.

**Delta badge — redesigned.** The current badge is `primaryColor25` with `text`
copy, so `+11%` and `-20%` look identical. Replaced with:

```
Container(
  padding: EdgeInsets.symmetric(horizontal: spacingMedium, vertical: spacingSmall),
  decoration: BoxDecoration(color: backgroundAlt,
                            borderRadius: BorderRadius.circular(radiusSmall)),
  child: Row(spacing: spacingSmall, [
    Icon(arrow, size: iconSizeTiny, color: tone, weight: iconWeight),
    Text(label, style: pSmallSemibold.copyWith(color: tone)),
  ]),
)
```
- arrow = `Symbols.arrow_upward_sharp` / `arrow_downward_sharp`;
  flat (delta 0 or null) → no icon, no badge.
- tone = `goodGreen` when the movement is good, `badRed` when bad, `text2nd` when
  neutral. Contrast on `backgroundAlt`: light 5.0:1 / 5.9:1, dark 6.4:1 / 5.1:1 —
  all clear AA.
- **Do not** use the `greenDark`/`redDark` tinted fills here: `goodGreen` on
  `greenDark` measures **3.27:1** and `badRed` on `redDark` **3.72:1** in light
  mode — both fail AA for text. (Same as DESIGN.md's table rule: status is colored
  text, never a filled cell.)
- "Good" direction per tile key comes from a client-side set. Up is **bad** for:
  `lost_members`, `churn`, `no_show_rate`, `refunds`, `failed_payments`,
  `outstanding`, `discounts_given`, `at_risk_members`. Everything else: up is good.

**Icon per tile key** (extend the existing `kpiSymbolFor` into a key→`Symbols` map;
default `Symbols.bar_chart_sharp`):
`total_members` `group_sharp` · `new_members` `person_add_sharp` ·
`lost_members` `person_remove_sharp` · `trial_members` `schedule_sharp` ·
`mrr` `payments_sharp` · `collected` `account_balance_wallet_sharp` ·
`refunds` `undo_sharp` · `failed_payments` `credit_card_off_sharp` ·
`avg_per_member` `person_sharp` · `discounts_given` `sell_sharp` ·
`outstanding` `pending_actions_sharp` · `checkins` `how_to_reg_sharp` ·
`avg_visits` `directions_run_sharp` · `no_show_rate` `event_busy_sharp` ·
`active_trials` `hourglass_top_sharp` · `conversion` `trending_up_sharp` ·
`churn` `trending_down_sharp` · `retention_90d` `verified_sharp` ·
`streaks` `local_fire_department_sharp` · `promotions` `military_tech_sharp` ·
`points_redeemed` `redeem_sharp` · `video_ctr` `play_circle_sharp`.

**Counts.** 1 tile → render at 25% width, left-aligned (a lone full-width tile
reads as a broken hero). 2–4 → equal `Expanded` columns, hairline-separated
(today's behaviour; 4 fits comfortably at ≥ 900px). 5–6 → wrap into rows of 4 with a
horizontal `Hairline` between rows. >6 → render the first 6 and log.

**States.** Empty (no tiles) → the whole section is omitted. A tile with a null
value renders `—` in `big2Light`/`text3rd` with no badge and the caption
`Not enough data yet`. No per-tile loading or error state — the page owns those.

### 4.2 `hero_split` — the money half-pie

**The page's one hero figure.** Exactly one per view (Overview, and Home).

**Container.** `SizedBox(width: min(available, heroChartHeight * 2), height: width / 2)`,
horizontally centered, with the legend below in a centered `IntrinsicWrap`
(`spacing: spacingLarge`, `runSpacing: spacingMedium`). Outer `Column(spacing: spacingBig)`.

**Geometry — generalizing `TotalMembersArc` from 2 segments to N.**

```
stroke = min(w / 2, h) * 0.09                    // 18 at 400x200 — unchanged ratio
r      = min(w / 2, h) - stroke / 2              // FIX: old code used
                                                 // shortestSide - stroke, which
                                                 // overflows when w < 2h and
                                                 // under-fills when w == 2h
c      = Offset(w / 2, h)                        // bottom-centre
rect   = Rect.fromCircle(center: c, radius: r)

start  = pi ; total = pi                         // left -> right, clockwise
gapRad = spacingMedium / r                       // an 8px visual gap, radius-independent
capRad = (stroke / 2) / r                        // round-cap overhang, in radians

// segments with value == 0 are dropped entirely (no gap is spent on them)
S          = sum(values)
boundary0  = pi
boundary_i+1 = boundary_i + pi * v_i / S

drawStart_i = boundary_i     + capRad + (i == 0     ? 0 : gapRad / 2)
drawEnd_i   = boundary_i+1   - capRad - (i == n - 1 ? 0 : gapRad / 2)
sweep_i     = drawEnd_i - drawStart_i
```

- `strokeCap: StrokeCap.round`, `PaintingStyle.stroke`, `strokeWidth = stroke`.
- Insetting the **outer** ends by `capRad` is a fix: the current painter lets the
  round caps bulge past the flat baseline. With the inset the half-pie's footprint
  is exactly the half-circle.
- Subtracting `gapRad / 2` from each side of every **interior** boundary makes the
  visual gap exactly `spacingMedium`, whatever N and whatever the radius. The
  current painter's constant `gapAngle = 0.18 rad` produces a different gap at
  every size.
- Sliver rule: if `sweep_i <= 0`, draw a filled circle of radius `stroke / 2` at
  the segment's mid-angle instead of an arc, so a tiny non-zero value stays visible
  and legendable.

**Segment color** — by `segment.tone`, falling back to the ramp by index:

| tone | color |
|---|---|
| `accent` / absent index 0 | `primaryColor` |
| absent index 1 | `darkPrimary` |
| `neutral` / `pending` / absent index ≥2 | `text3rd` |
| `good` | `goodGreen` |
| `warn` | `okYellow` |
| `bad` | `badRed` |

`revenue_hero` maps Collected → `accent`, Expected → `neutral`, Overdue → `warn`.
Measured: `primaryColor`/`text3rd`/`okYellow` clears the normal-vision floor at
17.7 (light) and holds CVD ≥ 12.3 in both modes; all three ≥ 3:1 on the ground.
Deep sapphire is deliberately **not** used for Expected — sapphire↔deep-sapphire
measures 13.6 in light, and neutral gray also reads correctly as "not money yet".

**Center label** — `Stack(alignment: bottomCenter)` over the arc, with
`Padding(bottom: paddingSmall)`:
```
Column(mainAxisSize: min, spacing: spacingSmall)
  Text(totalFormatted, style: big2Bold)                       // 32 / w700
  Text(caption,        style: h2Regular, color: text2nd)      // 16 / w400
```
Unit-aware total: `cents` → `formatMinorUnits(total, decimalDigits: 0)` (`$9,140`);
`count` → `NumberFormat.decimalPattern`; `percent` → `'41%'`.
Caption = `data.caption` (`Expected in July`). Home's current hero uses
`h1Regular` (24) for its caption — 32/24 is a 1.33 ratio that reads flat; 32/16 is
the correct step and drops the caption out of competition with the figure.

**Legend.** One `SubgroupLegendDot` per drawn segment, label
`'{segment.label} {formattedValue}'` (`Collected $7,920`) — no colon; the value is
part of the legend so identity never depends on matching a color to an arc.

**States.**
- `total == 0` or all segments zero → draw the full half-circle once in `line` as
  an empty track, and render `EmptyState.inline` beneath it in place of the legend
  (title `Nothing billed this month yet`).
- Loading / error → page-level only.

### 4.3 `line`

**Anatomy.** Section header (title / window / legend) → `Row[ y-axis column,
spacingMedium, Expanded(plot) ]` at `heroChartHeight` → `spacingMedium` →
x-axis label row.

**Marks.** §3, painted by `SplinePainter`. Series colors S1, S2 (ramp), then
residual. Max 3; more fold to `Other`.

**Series count.**
- 1 → no legend box (the title names it); area fill on; direct end label on.
- 2 → legend present; no area fill (two washes muddle); both end-labeled unless
  they collide.
- 3 → legend present; no fill; end-label the S1 series only.

**Points count.**
- 0 points, or all series empty → `EmptyState.inline(minHeight: heroChartHeight)`.
- 1 point → no spline; draw the end marker and its direct label, and set the
  section subtitle to `Only one period so far`.
- ≥ 2 → normal.

**Range pill** trims points before painting; if the trim leaves < 2 points the
1-point rule applies (never an empty plot from a filter).

### 4.4 `bars`

Same frame as `line`. Three modes, chosen deterministically:

| condition | mode |
|---|---|
| 1–2 series, no polar pair | **grouped** |
| ≥ 3 series | **stacked** |
| exactly 2 series and the metric key is in the polar set | **diverging** |

The polar set is a client-side constant containing `members_gained_lost` only
today. Grouping instead is a one-line change if the diverging form is rejected.

**Grouped.** Bars per §3, series left-to-right in ramp order within each slot,
`spacingSmall` gap between them, `spacingMedium` gutter between slots. Legend
required.

**Stacked.** One bar per slot; segments bottom-up in wire order (S1 at the bottom),
each shortened by `spacingSmall` at its top to create the surface gap; `topR` on
the topmost drawn segment only. Legend required. Direct labels only on the newest
bucket's total, above the bar, `pSmallSemibold` in `text`; never inside an interior
segment (it cannot fit and must not be clipped).

**Diverging.** Zero baseline at the plot's vertical centre, drawn full-width in
`line`. The `good`-tone series grows upward in `goodGreen`, the `bad`-tone series
downward in `badRed`. Y ticks become `+max / 0 / −max` on a symmetric scale.
Position, not hue, is the identity channel — required, because `goodGreen`↔`badRed`
measures ΔE 3.4 / 1.6 under deuteranopia and cannot carry identity alone. Legend
still present.

**Bucket count.** 1 bucket → render the single bar centered at `chartBarMaxWidth`
and add the subtitle `Only one period so far`. > 40 buckets → keep the newest 40 and
note it in the subtitle (`Showing the last 40 …`); the range pill is the real
control.

**Empty** → `EmptyState.inline(minHeight: heroChartHeight)`.

### 4.5 `breakdown`

Horizontal category bars. **No plot frame, no axis** — the value sits on the row.

```
Column(spacing: spacingMedium)
  for each item:
    Column(crossAxisAlignment: stretch, spacing: spacingSmall)
      Row[ Text(label, h3, text) , Spacer , Text(value, h3, text) ]
      SizedBox(height: spacingMedium, child: <track + fill>)
```
- Track: `line`, `BorderRadius.circular(radiusSmall)` (clamps to 4 on an 8px box).
- Fill: `primaryColor`, same radius, width fraction:
  - `unit == percent` → `value / 100` (absolute — a 39% fill rate must read as 39%
    of the track, not as "smallest of these four");
  - otherwise → `value / maxItemValue`.
- **All bars take slot 1.** Never ramp the fill by value: bar length already
  encodes magnitude, and re-encoding it in hue burns the identity channel.
- **Order** is wire order, always. The backend sorts (desc for nominal, natural for
  ordinal buckets and belt order). No client-side re-sorting — that is what makes a
  future metric drop in correctly.
- Value formatting per `unit`, as §3.

**Item count.** 0 → `EmptyState.inline(minHeight: heroChartHeight)`. 1 → render the
single row (do **not** promote it to a stat tile automatically; the section title
already frames it). > 8 → first 7 + a summed `Other` row in `text3rd`.

**`rank_distribution`** is the one breakdown with data-owned color: each row's fill
takes the rank's belt color when supplied, else `primaryColor`. Belt order comes
from the wire.

### 4.6 `donut_pair`

```
Center(
  Row(mainAxisSize: min, spacing: spacingBig, children: [
    SizedBox(height: heroChartHeight, child: AspectRatio(1, child: DonutStat(a))),
    SizedBox(height: heroChartHeight, child: AspectRatio(1, child: DonutStat(b))),
  ]))
```
The month-history table beside them is removed; the pair is centered so the section
does not read as left-weighted with 500px of dead space.

- `DonutStat` / `ProgressArc` reused unchanged, except `trackColor` is passed
  explicitly as `DesignConstants.line` (the default `card` paints a white ring on
  the de-carded ground).
- Ring color: donut 1 (the live period) `primaryColor`; donut 2 (the benchmark /
  gym average) `text3rd`. Today both are sapphire, which hides which one is the
  benchmark. Gray for the benchmark also matches the residual role.
- Center: `headline` `big2Bold`, `subLabel` `p` in `text2nd` (existing).
- `progress = pct / 100`, clamped 0–1 by `ProgressArc`.

**Counts.** 1 donut → render one, centered. ≥ 3 → render the first two and log.
**Empty** (null pct) → `EmptyState.inline(minHeight: heroChartHeight)`.

### 4.7 `heatmap`

Two shapes off one painter, distinguished by whether cells are labeled.

**Common cell.** Rect, no corner radius, `spacingSmall` gutter between cells in
both axes, fill from the §2.1-D density ramp bucketed by
`cell / maxCell` into 4 quartiles (0 → step 0). Every cell carries a 1px `line`
outline. Axis labels `pSmall` in `text3rd`.

**Busy times (unlabeled, `attendance_heatmap`).** Rows = weekdays (7), columns =
hours. Full width.
```
cellW = ((plotWidth - rowLabelWidth - gutters) / cols).clamp(16, 48)
cellH = cellW                                       // square
rowLabelWidth = intrinsic width of the widest row label + spacingMedium
```
Column labels every other column when `cellW < 28` (`6a`, `8a`, …). Scale legend in
the section title row, right-aligned: `Quiet` + four 12×12 swatches (steps 1–4) +
`Busy`, all `pSmall`/`text3rd`, `spacingSmall` between.

**Cohort grid (labeled, `cohort_retention`).** Half span. Row-label column 120px
wide (`h3`, `text`), three value columns of 96px, row height `tableRowHeight` (35).
- Cell label: the value, `pSmallSemibold`, color `DesignConstants.onFill(cellColor)`.
- **The density ramp caps at step 3 (75%)** for labeled grids: near-white on the
  full `primaryColor` measures 3.51:1 in dark, below AA; on step 3 it is 5.14:1 and
  ink on the light steps is 5.0–11.6:1.
- Immature cells (`null`) render `backgroundAlt` + 1px `line` + `pending` in
  `pSmall`/`text3rd`. No dashes anywhere — dashed strokes read as "projection".

**Empty** (no rows, or every cell zero/null) → `EmptyState.inline`.

### 4.8 `member_list`

`AppDataTable(shrinkWrap: true, stickyHeader: false)` with one
`AppDataTableColumn` per wire column and `AppDataTableRow.onTap` pushing
`AppRoutes.memberDetailPath(memberId)`. Every column is a **fill** column, so
they render **equal width**, sharing the row equally — no per-type `minWidth`.

| wire `type` | cell | align |
|---|---|---|
| `text` | `Text(v, style: h3)` | left |
| `number` | `Text(NumberFormat.decimalPattern().format(v), style: h3)` | right |
| `cents` | `Text(formatMinorUnits(v, decimalDigits: 0), style: h3)` | right |
| `date` | `Text(absoluteDate(v), style: h3, color: text2nd)` | left |

A numeric cell right-aligns inside its equal-width column via a
`SizedBox(width: infinity)` in `member_list_cells._cellText` — no per-column
align flag. **Dates render ABSOLUTE, never relative** (no "N days ago"): a
day-level member date (`started` / `last seen`) reads `DateFormat.yMMMd()`
(`Sep 5, 2026`); a companion table's monthly date reads `DateFormat.yMMM()`
(`Sep 2025`), keyed by the owning chart's `granularity` (see `absoluteDate` in
`member_list_cells.dart`). A null cell is an em-dash (`—`).

Row affordance: rows are already `InkWell` when `onTap` is set. The section
subtitle carries the instruction — `Select a member to open their profile` — rather
than adding a chevron column, which would spend a column on chrome.

**Rows.** 0 → `EmptyState.inline(minHeight: tableRowHeight * 4)`. Otherwise the
list shows **every** row (no hard cap): the table is wrapped in
`BoundedMetricTable` (§4.10), so a long at-risk / active-trials list scrolls
inside a fixed height rather than being truncated to a top-N.

### 4.9 Companion table — a `line` / `bars` add-on

A `line` / `bars` payload may carry an optional `table` (`MetricTable`):
`{ orientation, columns[], rows[] }`. When present the renderer shows the chart
**and** the table together; when absent (the common case) the chart renders
alone, unchanged. Members-over-time and Revenue-over-time are the two metrics
that carry one today (a per-month breakdown beneath the line).

- **Widgets.** `ChartWithCompanionTable(chart, table, granularity)` wraps the
  built chart; `MetricCompanionTable(table, granularity)` renders the table
  itself. Both live in `metric_renderers/companion_table_view.dart`. The table
  reuses `AppDataTable` (`shrinkWrap: true, stickyHeader: false`) and the
  **`member_list` cell formatter** (§4.8), so a chart's data table reads as a
  sibling of the page's other tables — de-carded, matching the page. Columns are
  **equal width** (all fill) and the whole table is wrapped in
  `BoundedMetricTable` (§4.10) so a 12-month breakdown scrolls inside a fixed
  height instead of dominating the tab. `granularity` is the owning chart's, so
  the Month column mirrors the month axis.
- **Cells format by column `type`,** exactly as `member_list` does: `date` →
  **absolute** date (a monthly table's Month column reads `Sep 2025` via
  `DateFormat.yMMM`, mirroring the chart's month axis — never relative "N days
  ago"); `cents` → `money.dart`; `number` → right-aligned grouped int; `text` →
  left. A **null cell renders as an em-dash** (`—`), never `null`, never `0` — an
  absent value and a zero are different facts.
- **Value cells are tinted by their column's `tone`** (`columnToneColor`):
  `good → goodGreen`, `bad → badRed`, `warn → okYellow`, and `neutral` / null /
  unknown → the default cell text color. This restores the old mockup's
  Gained-green / Lost-red / Retained-yellow read. Only value cells are tinted;
  the Month (`date`) column stays default, and an absent (null) cell keeps its
  muted em-dash regardless of tone.
- **Orientation.** `stacked` → `Column[chart, table]`, `spacing: spacingLarge`
  (the chart's own internal rhythm, so the table reads as one more block of the
  same body, not a tighter-bound appendage). `stacked` is the only orientation
  the backend emits today; `beside` and the resilient `unknown` fall back to
  the same stack — a side-by-side `Row` is a localized change in
  `ChartWithCompanionTable` if `beside` ever ships.
- **No row tap; every row shown, inside a bounded scroll.** Companion-table
  rows are aggregate per-bucket data (a per-month Gained / Lost / Retained /
  Trial breakdown), not members — so a row carries no member deep-link, and the
  table shows **every** row (bounded by the chart's own buckets, not a top-N).
  The `BoundedMetricTable` wrapper (§4.10) caps the *height* and scrolls the
  rows internally, so "every row" never means "dictates the tab's height".
- **Contract.** Mirrors `MetricTable` / `MetricTableColumn` / `MetricTableRow` /
  `TableOrientation` in `FastApiBackend/src/growth/schema/growth_schema.py`.
  `MetricTableColumn.type` reuses `MemberListColumnType` and carries an optional
  `tone` (`good` / `bad` / `warn` / `neutral` / null — the same vocabulary a
  `hero_split` segment's tone uses); a row's `cells` are positional against
  `columns`, each a `String`, a `double`, or null (the same normalisation
  `MemberListRow` uses). `TableOrientation` parses resiliently to `unknown`.
  `LineData` / `BarsData` gained a nullable `table` field.

### 4.10 `BoundedMetricTable` — the fixed-height scroll wrapper

Every growth table — the `member_list` renderer AND every companion table — is
wrapped in `BoundedMetricTable`
(`metric_renderers/bounded_metric_table.dart`) so the table never dictates the
tab's height. A 12-row companion breakdown or a long at-risk list would
otherwise dominate its tab; the wrapper caps the height and scrolls the rows
inside it.

- **Cap:** `DesignConstants.growthTableMaxHeight` (`tableRowHeight * 8`, §10) is
  the max viewport height — a handful of rows. It is a `maxHeight`
  (`ConstrainedBox`), not a fixed height, so a short table still renders at its
  natural height; only a long one caps and scrolls.
- **Convention:** matches the member-detail history cards — an explicit
  `ScrollController`, an always-visible thumb (`thumbVisibility: true`), and a
  `spacingLarge` right gutter so the thumb clears the last column. The section
  title above stays put; only the rows scroll.
- The wrapped `AppDataTable` keeps `stickyHeader: false`: its header row scrolls
  with the rows, exactly as the history cards' tables do — the section's own
  metric-name title is the pinned heading.

---

## 5. Shared states

### 5.1 `EmptyState` — the new shared primitive

There is no shared empty-state widget in the CRM today; each screen hand-rolls one
(`ranks_tab.dart::_ReadyEmpty` is the best of them). This formalizes that exact
pattern into `lib/shared/widgets/empty_state.dart`.

```dart
EmptyState({
  IconData? icon,                 // Symbols.*_sharp
  required String title,
  String? body,
  Widget? action,                 // AppOutlineButton
  EmptyStateTone tone = EmptyStateTone.neutral,   // neutral | error
  double? minHeight,              // reserve the slot the content would have taken
})
EmptyState.inline({...})          // convenience: minHeight set, no action
```

**Anatomy** — centered, `Column(mainAxisSize: min, spacing: spacingLarge)`:
| part | token |
|---|---|
| icon | `iconSizeBig` (32), `weight: iconWeight`, color `text3rd` (neutral) / `badRed` (error) |
| text block | `Column(mainAxisSize: min, spacing: spacingSmall)` |
| title | `h2`, color `text2nd` |
| body | `p`, color `text3rd`, `textAlign: center`, `ConstrainedBox(maxWidth: dialogMaxWidth)` (≈65ch at 12px) |
| action | `AppOutlineButton` |

`minHeight` wraps the whole thing in
`ConstrainedBox(constraints: BoxConstraints(minHeight: minHeight))` so a chart's
empty state occupies the chart's height and the page does not reflow when data
arrives.

**Per-renderer copy templates** — generic, with the metric's `name` interpolated,
so a new metric of a known type gets correct copy with zero design work:

| renderer | title | body |
|---|---|---|
| `line`, `bars` | `No {name} history yet` | `This fills in as the gym records data. Check back after your first full month.` |
| `breakdown` | `No {name} to show` | `Categories appear here once members are assigned to them.` |
| `donut_pair` | `Not enough history yet` | `Needs at least one full month of members to compare against.` |
| `heatmap` | `No {name} yet` | `The grid fills in as check-ins are recorded.` |
| `member_list` (at-risk) | `Nobody is at risk right now` | `Members appear here when they have not checked in for 14 days.` |
| `member_list` (trials) | `No active trials` | `Members on a trial plan appear here while their window is open.` |
| `hero_split` | `Nothing billed this month yet` | `Collected, expected and overdue amounts appear once invoices go out.` |
| `kpi_group` tile | `—` in place of the value | caption becomes `Not enough data yet` |

Icons: `line`/`bars` `Symbols.show_chart_sharp` · `breakdown`
`Symbols.bar_chart_sharp` · `donut_pair` `Symbols.donut_large_sharp` · `heatmap`
`Symbols.grid_view_sharp` · `member_list` `Symbols.group_sharp` · `hero_split`
`Symbols.payments_sharp`.

Empty copy follows the ux-writing rule — acknowledge, then say what makes it fill —
never a bare "No data".

### 5.2 Loading

**Confirmed: a centered `AppSpinner`, not skeletons.** The general product rule
prefers skeletons over spinners, but it assumes per-region loads. Growth is a
**single** backend read serving all six tabs — there is no partial content to
skeleton around, and 28 skeleton shapes would be more chrome than the page has
content. Skeletons here would be cosplay.

- **Initial load** — the tab body is replaced by
  `Center(child: AppSpinner(size: spinnerSizeLarge))` at
  `minHeight: heroChartHeight * 2`. Chrome (tab bar, meta row) stays mounted; the
  range pill is rendered disabled (`onSelected: null`, labels at `text3rd`).
- **Refetch** (manual refresh, gym switch) — **hold the previous render** at 60%
  opacity via `Opacity`, with the small spinner in the freshness stamp (§1.3). No
  layout jump, no skeleton flash.
- **Filter changes** (range pill, class chips) are pure client-side reshapes:
  synchronous, no loading state at all.

### 5.3 "Not computed yet"

`computed_at == null && metrics.isEmpty`. Replaces the whole tab body (chrome stays,
pills hidden):

```
EmptyState(
  icon:  Symbols.query_stats_sharp,
  title: 'Your metrics are still being built',
  body:  'Growth recomputes every hour. The first run usually lands within an '
         'hour of your gym going live.',
  // No action, deliberately.
)
```

**No retry button here** — this is the one empty state that must not offer one.
Nothing the user can press changes the outcome: the metrics are absent because
the backend's hourly sweep has not run for this gym yet, so a "Check again" that
re-fetches the same empty response would read as a failure the user could fix,
and reward pressing it with no change. Contrast §5.4, where a retry is genuinely
the right affordance because the request itself failed.

### 5.4 Error

Page-level failure replaces the tab body:

```
EmptyState(
  tone:  EmptyStateTone.error,
  icon:  Symbols.error_sharp,
  title: "Couldn't load your metrics",
  body:  <friendly message from the typed exception>,
  action: AppOutlineButton(text: 'Try again', onPressed: reload),
)
```

The existing inline `ErrorMessage` banner is kept for a **partial** failure: if the
response arrives but one metric's `data` fails to parse, that section renders
`ErrorMessage('This metric could not be read.')` in place of its body and the rest
of the page is unaffected. One bad envelope must never blank the page.

---

## 6. Tab composition

Order within a tab is the envelope's `order`; the lists below are that order with
spans applied. `|` marks two half-span metrics sharing one row.

The tab order is Overview · Revenue · Members · Retention · Trial · Attendance
(§1.2).

**Overview** — `revenue_hero` (hero) · `members_kpis` · `members_trend` ·
`avg_membership_length`.
The hero is first and is the page's only hero figure; everything below it is
supporting. Three hairlines. Overview leads with Average Membership Length as its
retention read — an owner reads "members stay N months" more readily than a churn
percentage.

**Revenue** — `revenue_kpis` · `mrr_trend` · `revenue_collected` (stacked ×3:
Card S1 / Cash S2 / Other residual) · `revenue_by_plan` · `revenue_quality_kpis`.
MRR-first: the headline stat then its own history directly beneath it. `mrr_trend`
is also drawn on the Home dashboard by `RevenueTrendCard` (owner/admin only, under
the money hero) — the line only, `showCompanionTable: false`, never its per-month
table.

**Members** — `members_kpis` · `members_trend` · `members_gained_lost` ·
`members_by_plan` · `membership_status_mix` | `member_tenure`.

**Retention** — `retention_kpis` · `churn_trend` · `avg_membership_length` ·
`cohort_retention` | `rank_distribution` · `at_risk_members` · `engagement_kpis` ·
`promotions_trend` | `redemptions_trend` · `video_engagement` (line ×2: Clicked S1,
Served S2).
Cause up top (churn, cohorts, at-risk), the engagement loop that drives it below —
one scroll, cause then effect. This is the longest tab; that is acceptable for the
one tab an owner reads end to end. Churn is a `line` here now (`churn_trend`), not a
donut — the dropped `churn_donuts` metric left the `donut_pair` renderer in place
for a future donut metric.

**Trial** — `trial_kpis` · `trials_started_vs_converted` (grouped: Converted S1,
Started S2) · `trial_conversion_trend` · `trial_outcomes` | `trial_engagement` ·
`active_trials`.

**Attendance** — class chips active. `attendance_kpis` · `checkins_trend` ·
`attendance_heatmap` · `attendance_by_class` | `class_fill_rate` ·
`signups_vs_checkins` (grouped: Check-ins S1, Sign-ups S2 — the achieved value gets
the accent, so no-shows read as the gap).

---

## 7. Responsive

One breakpoint: `navMobileBreakpoint` (768). Above it, desktop. Below it the nav
rail is already a hamburger, so the content owns the full width.

| element | below 768 |
|---|---|
| `ViewSwitcher` | `textStyle: DesignConstants.h3` (fits to ~430px) |
| meta row | `IntrinsicWrap` wraps: stamp on line 1, pills on line 2 |
| `kpi_group` | 2×2 grid — two `Expanded` columns with `Hairline(vertical: true)`, rows separated by a horizontal `Hairline` |
| all `half` spans | become `full` |
| `hero_split` | `width = min(available, heroChartHeight * 2)`, `height = width / 2` — scales, never overflows |
| `line` / `bars` | plot height unchanged (200); x labels decimate via the `plotWidth / 56` rule |
| `breakdown` | unchanged (already fluid) |
| `donut_pair` | stacks vertically, `spacingBig`, still centered |
| `heatmap` (busy) | `cellW` clamps at its 16px floor: 16 cols × 16 + gutters ≈ 300px, fits |
| `heatmap` (cohort) | fixed 120 + 3×96 + gutters ≈ 420px, fits |
| `member_list` | `AppDataTable` horizontal-scrolls below its min width (existing behaviour) |

No fluid typography anywhere — hierarchy is fixed-step, per the product register.

---

## 8. Accessibility

- **Contrast, marks vs the page ground** (`backgroundColor`): `primaryColor` 5.10
  light / 4.36 dark · `darkPrimary` 8.53 / 2.30 · `text3rd` 3.05 / 5.25 ·
  `okYellow` 5.14 / 7.91. `darkPrimary` in dark mode is the one mark below 3:1;
  its relief is mandatory (legend with value + direct label), and it is only ever
  used as the S2 companion beside a compliant S1.
- **Contrast, labels inside fills**: heat cells use `onFill(cellColor)` —
  5.57:1 (white on `primaryColor`, light) / 5.14:1 (near-white on step 3, dark) /
  11.55:1 (ink on step 1, light). Labeled grids cap at step 3 for exactly this
  reason.
- **Never color-alone.** ≥2 series always ship a legend carrying each series'
  value; `breakdown` prints the value on every row; `line` direct-labels its
  endpoints; the good/bad pair is encoded by position (diverging), not hue; KPI
  deltas carry a direction arrow beside the tone.
- **CVD.** Measured adjacent-pair separation is recorded in §2.3 with its two
  documented deviations and their mitigations. `goodGreen`/`badRed` are never
  adjacent as an identity channel.
- **Motion.** `AppSpinner` already honours `disableAnimations`. Nothing else on
  this page animates; chart entrance animation is deliberately out of scope
  ("no orchestrated page-load sequences" — users load into a task).
- **Semantics.** Each chart section wraps its painter in
  `Semantics(label: '{name}, {window}', value: <the summary sentence>)` — for a
  `line`, `'{latest label}: {latest value}'`; for `breakdown`, the top item.
  Painted charts are otherwise invisible to a screen reader.

---

## 9. What changed from the wireframes, and why

1. **Gained vs Lost is a diverging bar (good up / bad down), not grouped bars.**
   `goodGreen`↔`badRed` measures ΔE 3.4 (light) / 1.6 (dark) under deuteranopia —
   a full collapse, well below the ΔE 6 floor, which no amount of legend fixes. The
   diverging form makes position the identity channel and is also the standard read
   for a net-change chart. Reversible to grouped-with-the-sapphire-ramp in one line
   if the diverging form is not wanted.
2. **The hero's "Expected" segment is `text3rd` (neutral), not a soft sapphire.**
   The wireframe annotation says "soft"; `accentSoft` measures ~1.1:1 on the ground
   (invisible as a fill) and deep sapphire measures ΔE 13.6 against `primaryColor`
   in light. Neutral gray clears the floor at 17.7 and reads correctly as
   "not money yet".
3. **The `donut_pair` benchmark ring is `text3rd`, not sapphire.** Two identical
   sapphire rings hide which one is the benchmark.
4. **Section titles are `h2` (16), not `h1` (24).** DESIGN.md assigns `h1` to page
   titles; with 6–10 sections per tab, `h1` everywhere competes with the hero.
5. **No repeated tab title under the tab bar.** The Gym screen's `big2` title row
   exists to hold its Add button; Growth has no primary action, so the title would
   restate the lit tab.
6. **Y-axis ticks move to the left of the plot,** and the current `'140 -'` faux
   tick marks become real hairline gridlines.
7. **Added: a hover read-out on `line` and `bars`.** Not in the wireframes. A
   `MouseRegion` over the plot resolves the nearest x-bucket and draws a 1px `line`
   crosshair plus a small `popup`-filled card (`radiusSmall`, `cardShadow`,
   `pSmallSemibold` value, `pSmall`/`text3rd` label) anchored above the bucket.
   Values remain readable without it (axis ticks + direct end labels), so it is an
   enhancement, not a gate — but on a desktop metrics page a bar chart with no
   per-bucket read-out is genuinely hard to use. **Flagging for a decision:** cut it
   and the spec still ships whole.
8. **Cohort "pending" cells stay as the word `pending`** (as wireframed) rather
   than an em-dash, and are drawn with a solid `line` outline — no dashed strokes.

Nothing in the six-tab IA, the metric-to-tab assignment, or the renderer set was
changed.

### Chart fixes (live-metrics pass)

9. **The chart legend value is the series' total over the shown window, not its
   newest bucket.** Each `line` / `bars` legend entry reads `{label} {value}`
   where `value` is the **sum of that series over the currently-shown
   (range-trimmed) points** — the range pill trims a series before the bundle is
   built, so the legend total always matches exactly what the chart draws. The
   old value was the latest bucket, which sat misleading beside a full chart the
   moment the newest period was still filling in (e.g. `Check-ins 0` for the
   current, incomplete week next to a full-year chart). Implemented as
   `DrawnSeries.total`, read in `line_view` / `bars_view`.
10. **A `line`'s y-axis is `0..niceCeiling(max)` — never negative.** Verified
    against live data: `members_trend` (a single count series, 2 → 107) draws a
    correct `200 / 100 / 0` axis with the line filled in. Negatives belong
    **only** to the `bars` diverging mode (§4.4): `members_gained_lost` correctly
    carries `+max / 0 / −max`, which is where the `−100` tick on the Members tab
    comes from — the diverging bars, not the line. A count / cents line never
    carries a negative tick (`niceCeiling` floors at 1; `yTicksFor` is
    `[max, max/2, 0]`). A regression guard asserts the line painter receives
    non-empty points on a non-negative scale.
11. **Churn is a `line`, not a `donut_pair`.** The backend dropped the
    `churn_donuts` metric; churn is now `churn_trend` (a `line`) on Retention,
    and Overview leads with `avg_membership_length` (also a line) as its
    retention read — both rendered generically by category. The `donut_pair`
    renderer stays in place, unused, ready for a future donut metric. The stale
    `churn_donuts` window-label entry (`growth_metric_registry.dart`) and the §6
    Overview / Retention `churn_donuts` mentions have been removed.

### Table + tab polish (live-metrics pass, cont.)

12. **Every growth table is height-bounded with an internal scroll**
    (`BoundedMetricTable`, §4.10) — companion tables and member lists both. A
    long table scrolls inside `growthTableMaxHeight` (§10) instead of dictating
    the tab's height; the `member_list` ten-row hard cap is gone (all rows show,
    inside the scroll).
13. **Table `date` cells render absolute, never relative** (§4.8): a monthly
    companion table's Month column reads `Sep 2025` (mirroring the chart's month
    axis); member dates read `Sep 5, 2026`. The old relative "N days ago"
    rendering is gone.
14. **Growth table columns are equal width** (all fill columns, §4.8) instead of
    content-sized.
15. **Companion value cells are tinted by their column `tone`** (§4.9) —
    Gained-green / Lost-red / Retained-yellow — mirroring the new
    `MetricTableColumn.tone` contract field.
16. **Tabs reordered** to Overview · Revenue · Members · Retention · Trial ·
    Attendance (§1.2); the route constants are unchanged, only their list order.
17. **Home dashboard gains a revenue-over-time card** (`RevenueTrendCard`) under
    the money hero, owner/admin only — the `mrr_trend` line only, never its
    companion table (§6 Revenue note).

### Pre-existing issues surfaced (not silently inherited)

- `TotalMembersArc` computes `radius = shortestSide - strokeWidth`, which overflows
  horizontally whenever `w < 2h` and under-fills the box at `w == 2h`. Corrected in
  §4.2 to `min(w / 2, h) - stroke / 2`.
- The same painter's round caps bulge past the flat baseline (no `capRad` inset),
  and its fixed `gapAngle = 0.18` produces a different visual gap at every size.
  Both corrected.
- The KPI delta badge is colorless — `+11%` and `-20%` render identically. Redesigned
  in §4.1.
- `ProgressArc` defaults `trackColor` to `card`, which paints a white ring on the
  de-carded ground. Every Growth call site passes `line` explicitly.
- The `*Dark` tinted status chips (`greenDark`, `redDark`, `yellowDark`) carry their
  status hue as text at **3.27–3.72:1** in light mode — below AA. Growth does not use
  them; wherever else they carry text, they are an AA failure worth a separate fix.
- `DesignConstants.baseFont` hardcodes `FontFeature.tabularFigures()` on every
  style, so the hero figure and KPI values render with tabular digits, which look
  loose at 32px. This is a deliberate system-wide choice in DESIGN.md
  ("tabular figures everywhere") and is **not** changed for this page — noted only
  so it is a known trade, not an oversight.

---

## 10. Proposed new tokens

Three geometry constants. No new colors are required.

| token | value | why an existing token will not do |
|---|---|---|
| `chartStroke` | `2.0` | The chart line weight. `dividerThickness` (1) is a hairline, `progressBarThickness` (4) is a progress rail, `buttonBorder` (2) is a button border. Today `_MembersTrendLinePainter` hardcodes `3` with a comment saying no token exists. |
| `chartBarMaxWidth` | `24.0` | The cap on bar thickness. Coincides with `iconSizeLarge`, but icon sizes are reserved for `Icon()` — the same rule that already keeps `spinnerSizeSmall` and `legendDotSize` separate from `iconSize*`. |
| `growthTableMaxHeight` | `tableRowHeight * 8` | The scroll-viewport cap for a growth table (`BoundedMetricTable`, §4.10) — about eight rows. Derived from `tableRowHeight` so it tracks the row height; not `historyCardHeight` (560), which is a member-detail card's own fixed height, nor a chart height. |

**Optional, only if the ΔE-15 normal-vision floor must be cleared everywhere**
(§2.3): a `chartSeries2` pair replacing `darkPrimary` as S2 — light around
`#5B7FA8`-family violet/teal, dark its lightened twin — chosen by running the
dataviz validator against `primaryColor` and `text3rd` in both modes until the
worst adjacent pair clears 15. Not recommended unless the founder wants the floor
cleared: it adds a second chart hue to a deliberately single-accent system, and the
two current deviations (13.6 / 13.7) sit just under a conservative floor with full
secondary encoding in place.

---

## 11. Open questions

1. **`class_fill_rate` thresholds.** A 39%-full class probably wants to be flagged
   `okYellow`/`badRed`, but the thresholds are a business decision. Spec'd as
   all-sapphire until the bands are set.
2. **Belt colors for `rank_distribution`.** The wireframe annotation says
   production tints each bar to its real belt color, but the `breakdown` envelope
   has no color field and `gym_ranks` stores a belt *image*, not a hex. Either add
   `items[].color` to the envelope, or drop belt tinting. Renders correctly in
   sapphire either way.
3. **Window labels on the wire.** §1.5 uses a client-side registry so no backend
   change is needed. Adding `window_label` to the envelope would be cleaner (one
   source of truth, and a new metric would arrive self-describing). Backend
   contract change — founder's call.
4. **Hover read-out** (§9.7) — in or out.
5. **`AppDataTableColumn.align`** — a small shared-widget extension `member_list`
   needs for right-aligned numbers. Confirming it is fine to land here rather than
   wrapping cells in a Growth-local hack.
