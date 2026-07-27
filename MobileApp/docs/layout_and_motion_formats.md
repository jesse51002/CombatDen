# Layout and motion formats — the enum library

The seed library of **arrangement variants** for the CombatDen member app, written
as JSX so the shape of each layout is readable at a glance and diffable against
its siblings.

This is the reference-implementation half of the direction set in
`docs/Business/pivots/2026-07-27-11-customization-engine-is-the-company.md`. It is
the concrete form of Open Question 12's preferred answer:

> *"an easier way could be legitabely just making an enum for each new layo9u it
> makes and then you can just maintain the enum of stuff and everything is on
> main."*

Nothing here forks. Each generated layout becomes one more value on an enum that
lives on trunk, and a tenant selects one.

---

## 1. The rule: one enum per screen

**Each major screen owns exactly one layout enum. Each value of that enum is one
complete, human-reviewed arrangement of that screen.**

The alternative considered and rejected was composable per-region slots (a topbar
enum × a schedule enum × a hero enum). It is rejected on three grounds, all of
them from the pivot:

- **P15 — keep the token layer strictly orthogonal to layout.** Region slots do
  the opposite inside the layout layer itself: 4 topbars × 4 schedules × 4 heroes
  is 64 home screens, and every one of them is something a person has to look at.
  The review surface must *add*, not multiply.
- **T10 — layout has no deterministic accept condition.** Colour resolves against
  WCAG and OKLCH. There is no formula for "is this arrangement good", so human
  judgment is the throughput ceiling. Whole-screen values keep the count of things
  needing judgment equal to the count of things shipped.
- **P14 — functional equivalence.** The invariant is checkable per screen. A
  whole-screen value has one element multiset to diff. Composed regions have to be
  checked per combination.

The one factored-out exception is the **shell** (topbar + bottom nav), because it
frames every screen rather than belonging to any one of them. It is reviewed once
against one screen and then composes without changing any body. That is additive,
not multiplicative.

**Review math:** `shell(4) + home(5) + videos(5) + rank(5) + rewards(5) +
class(5) + celebration(5)` = **34 arrangements to review**, not 15,625 combinations.

## 2. The invariant, and the gate it gives you for free

P14 says a redesign changes arrangement only. No screen merged or split, no
functionality added, none removed, no new data.

Because every variant below is written against the **same component set** as the
shipped screen, that invariant reduces to a mechanical check:

```
multiset(components in variant) == multiset(components in baseline)
```

Same components, same count, same props that carry data. Only nesting, order, and
presentation props may differ. That is a linter, not an argument, and it is the
thing T11 says has never actually been checked:

> **T11** — Does the functional-equivalence gate actually pass on real variants?
> P14 is a strong claim precisely because it is checkable. It has never been
> checked. Build the gate against the existing CombatDen app first, before it is
> ever promised to a customer.

This library is the corpus to check it against. Each screen below opens with its
`INVARIANT` block: the exact multiset every value of that enum must contain.

**Props split into two kinds, and only one kind is free:**

| Prop kind | Example | May a variant change it? |
|---|---|---|
| Data props | `video={featured}`, `points={data.totalPoints}` | **No.** Changing these changes what is fetched or shown. |
| Presentation props | `layout="stacked"`, `pinned`, `axis="horizontal"` | **Yes.** This is the whole surface a variant may move. |

## 3. Layouts are drawn without brand

Every wireframe in the companion preview page is deliberately unstyled: grey
blocks, one neutral fill for the primary action, no CombatDen orange, no Jura.

That is not laziness, it is the P15 test made visible. **If a layout only works
under one palette or one typeface, it is not a layout, it is a theme, and it has
leaked across the orthogonality boundary.** A value that reads as broken in
greyscale gets rejected at review rather than shipped and discovered later on a
tenant with a light canvas.

The CombatDen brand rules in `MobileApp/PRODUCT.md` (dark canvas, orange reserved
for agency, celebration rationed to post-class) describe *the reference
implementation's token set*. They are not constraints on the layout library, and a
layout that assumes them is a bug.

---

## How to switch formats and validate one

A format is selected from the tenant's customization slot in production,
but that is useless for review. There are three ways to pin one
deterministically, highest precedence first.

**1. Run the app with a flag.** The fastest way to see a real, fully
themed screen. Same mechanism as the existing `--dart-define=VIDEO_BASE_URL`.

```sh
flutter run --dart-define=SHELL_FORMAT=compactRail
flutter run --dart-define=SHELL_FORMAT=markOnly \
            --dart-define=MOTION_PERSONALITY=calm
```

Flag names are the slot id upper-cased: `SHELL_FORMAT`, `HOME_FORMAT`,
`VIDEOS_FORMAT`, `RANK_FORMAT`, `REWARDS_FORMAT`, `CLASS_FORMAT`,
`CELEBRATION_FORMAT`, `MOTION_PERSONALITY`, `CELEBRATION_INTRO`,
`REVEAL_STYLE`, `LOADER_STYLE`, `TRANSITION_STYLE`, `COUNT_UP_STYLE`.
An unrecognised value falls back to the shipped arrangement rather than
breaking the screen, so a typo is harmless.

**2. Generate the preview sheet.** Renders every value of an enum to a
PNG side by side, with no emulator and no backends running.

```sh
flutter test --tags golden --update-goldens --run-skipped
# writes test/goldens/shell_<value>.png, one per enum value
```

Each panel labels its own enum value. Read these for *arrangement*
only: assets are stubbed to grey placeholder blocks and the brand font
is not fetched, so type and artwork are not represented.

**3. Set the slot on the tenant.** The production path. Put the value in
the tenant's resolved text slots (`app_shell_format: compactRail`) and
the app picks it up on next launch with no rebuild.

**And to prove a format did not break the contract:**

```sh
flutter test          # the invariant gates; must stay green
```

---

# Layout enums

## 3.1 `app_shell_format`

The chrome that frames every screen. Files: `shared/widgets/topbar/app_topbar.dart`,
`shared/widgets/nav/app_bottom_nav_bar.dart`.

```
INVARIANT
  GymLogo ×0..1     (present iff the screen passes AppTopbarMode.bigLogo;
                     markOnly is the one value that always shows it)
  GymName ×1        GymSwitchChevron ×1
  RankBadge ×1      StreakStat ×1     PointsStat ×1     QrAction ×1
  BackButton ×0..1  (present only where the screen passes showBackButton)
  NavItem ×4        (home, rank, reward, videos — order is fixed, it is muscle memory)
```

> [!warning] Two corrections found while implementing this enum.
> The first draft of this invariant was wrong in two ways, and building
> against the real widgets is what exposed both.
>
> 1. **`InfoBar` has FOUR items, not three.** Alongside rank, streak and
>    points there is a **QR action** — the in-gym scan entry point, which
>    is the first step of the engagement loop. A variant that dropped it
>    would have broken the loop, not just the layout.
> 2. **`GymLogo` is not unconditional.** `AppTopbarMode.nameOnly` (every
>    screen except home) ships with no mark at all, so a flat `×1` would
>    have forced a logo onto screens that never had one.
>
> This is the argument for the gate being executable rather than a
> written contract: a prose invariant was wrong twice, and
> `test/shell_invariants_test.dart` would have caught both on the first
> run.

### `stacked` — shipped today

Large square logo above the centred gym name, stats in a full-width bar beneath,
four-up icon+label nav.

```jsx
<AppShell>
  <AppTopbar>
    <TopbarHeaderSection align="center">
      <GymLogo size="lg" />
      <GymName />
      <GymSwitchChevron />
    </TopbarHeaderSection>
    <InfoBar layout="spread">
      <StreakStat /><PointsStat /><RankBadge />
    </InfoBar>
  </AppTopbar>

  <AppBottomNavBar layout="fourUp" labels>
    <NavItem tab="home" /><NavItem tab="rank" />
    <NavItem tab="reward" /><NavItem tab="videos" />
  </AppBottomNavBar>
</AppShell>
```

### `compactRail`

One row: mark on the left, name centred, stats collapsed into a right-hand cluster.
Buys back roughly 180px of vertical space on every screen, which is the whole point
of the value.

```jsx
<AppShell>
  <AppTopbar height="compact">
    <TopbarHeaderSection align="spaceBetween" axis="horizontal">
      <GymLogo size="sm" />
      <Group><GymName /><GymSwitchChevron /></Group>
      <InfoBar layout="cluster" density="tight">
        <StreakStat /><PointsStat /><RankBadge />
      </InfoBar>
    </TopbarHeaderSection>
  </AppTopbar>

  <AppBottomNavBar layout="fourUp" labels>
    <NavItem tab="home" /><NavItem tab="rank" />
    <NavItem tab="reward" /><NavItem tab="videos" />
  </AppBottomNavBar>
</AppShell>
```

### `statFirst`

Stats are promoted above identity. For a tenant whose retention story is the
numbers rather than the brand mark.

```jsx
<AppShell>
  <AppTopbar>
    <InfoBar layout="spread" emphasis="primary" position="top">
      <StreakStat size="lg" /><PointsStat size="lg" /><RankBadge size="lg" />
    </InfoBar>
    <TopbarHeaderSection align="center" density="tight">
      <GymLogo size="xs" /><GymName scale="sm" /><GymSwitchChevron />
    </TopbarHeaderSection>
  </AppTopbar>

  <AppBottomNavBar layout="fourUp" labels>
    <NavItem tab="home" /><NavItem tab="rank" />
    <NavItem tab="reward" /><NavItem tab="videos" />
  </AppBottomNavBar>
</AppShell>
```

### `markOnly`

Logo alone, no name text, stats inline on one baseline, nav as a floating pill.
The most "consumer app" of the four and the one that most changes the app's read.

```jsx
<AppShell>
  <AppTopbar height="compact" rule={false}>
    <TopbarHeaderSection align="center">
      <GymLogo size="md" />
      <GymName visuallyHidden />          {/* still rendered for a11y + switch target */}
      <GymSwitchChevron />
    </TopbarHeaderSection>
    <InfoBar layout="inline" density="tight">
      <StreakStat /><PointsStat /><RankBadge />
    </InfoBar>
  </AppTopbar>

  <AppBottomNavBar layout="floatingPill" labels={false}>
    <NavItem tab="home" /><NavItem tab="rank" />
    <NavItem tab="reward" /><NavItem tab="videos" />
  </AppBottomNavBar>
</AppShell>
```

> [!warning] `markOnly` drops the visible gym name.
> The name is still in the tree (screen readers, switch-gym target), so the
> invariant holds, but for a white-label tenant whose whole ask is "make it look
> like us" a hidden name may be the wrong default. Flagged, not decided.

---

## 3.2 `home_format`

Files: `features/home/presentation/screens/home_screen.dart` and the two bodies
under `widgets/home_body/`.

```
INVARIANT
  AppTopbar ×1
  UpcomingSessionsCard ×1      (booked body only; the not-booked body omits it in
                                every variant — that is the existing state split,
                                not an arrangement change)
  ClassScheduleTitle ×1
  DateRow ×1  with  DateTab ×n
  DayClassGroup ×n  with  ClassListItem ×n
  ClassListItem carries: title, time, instructor, bookingsCount, thumbnail, tap→classDetail
  ScheduleStatus ×1            (loading | error | empty; one of three, never zero)
  AppBottomNavBar ×1
```

### `agendaList` — shipped today

Pinned date rail over vertical day groups, each class a text-left / thumb-right row.

```jsx
<HomeScreen>
  <AppTopbar mode="bigLogo" />
  <UpcomingSessionsCard />
  <ClassScheduleTitle />

  <DateRow pinned scroll="horizontal">
    <DateTab />…
  </DateRow>

  <ScheduleStatus />
  <DayClassGroup>
    <ClassListItem layout="textLeft-thumbRight" thumb="16:9-sm" divider />
  </DayClassGroup>…

  <AppBottomNavBar />
</HomeScreen>
```

### `dayPager`

The date rail becomes the primary control: one day per page, swiped. Classes are
wide media cards, image on top. Trades cross-day scanning for a much stronger
single-day read.

```jsx
<HomeScreen>
  <AppTopbar mode="bigLogo" />
  <UpcomingSessionsCard />
  <ClassScheduleTitle />

  <DateRow pinned control="pager">
    <DateTab />…
  </DateRow>

  <ScheduleStatus />
  <DayClassGroup axis="page">
    <ClassListItem layout="imageTop-metaBelow" thumb="16:9-full" />
  </DayClassGroup>…

  <AppBottomNavBar />
</HomeScreen>
```

### `timeSpine`

A left time gutter runs as a vertical spine; classes hang off their own start time.
The thumbnail demotes to a small leading avatar. Reads as a real timetable, which
is what a member with three classes in one evening actually needs.

```jsx
<HomeScreen>
  <AppTopbar mode="bigLogo" />
  <UpcomingSessionsCard />
  <ClassScheduleTitle />

  <DateRow pinned scroll="horizontal">
    <DateTab />…
  </DateRow>

  <ScheduleStatus />
  <DayClassGroup gutter="time">
    <ClassListItem layout="spine" thumb="avatar-sm" rule="hairline" />
  </DayClassGroup>…

  <AppBottomNavBar />
</HomeScreen>
```

### `nextUpHero`

The next class becomes a full-bleed hero at the top; everything after it collapses
into a dense list. The most opinionated value and the one that best serves the
"before class, in a hurry" moment in `PRODUCT.md`.

```jsx
<HomeScreen>
  <AppTopbar mode="nameOnly" />
  <UpcomingSessionsCard layout="hero" bleed />
  <ClassScheduleTitle />

  <DateRow control="segmented">
    <DateTab />…
  </DateRow>

  <ScheduleStatus />
  <DayClassGroup density="compact">
    <ClassListItem layout="dense" thumb="none" rule="hairline" />
  </DayClassGroup>…

  <AppBottomNavBar />
</HomeScreen>
```

> `thumb="none"` hides the class image. The image is still bound and still
> reachable on the detail screen, so no data need changes, but this is the one
> home value that removes a visual affordance rather than moving it. It belongs in
> the library; whether it is offered as a default is a separate call.

### `boardGrid`

Two-up card grid per day under a sticky day header. Highest density per scroll,
weakest time hierarchy.

```jsx
<HomeScreen>
  <AppTopbar mode="bigLogo" />
  <UpcomingSessionsCard layout="chipStrip" />
  <ClassScheduleTitle />

  <DateRow pinned="perSection" scroll="horizontal">
    <DateTab />…
  </DateRow>

  <ScheduleStatus />
  <DayClassGroup layout="grid" columns={2}>
    <ClassListItem layout="card" thumb="4:3" />
  </DayClassGroup>…

  <AppBottomNavBar />
</HomeScreen>
```

---

## 3.3 `videos_format`

Files: `features/videos/presentation/screens/videos_screen.dart`,
`widgets/videos_feed_body.dart`.

```
INVARIANT
  AppTopbar ×1
  VideoCategoryTabs ×1         (All + one per big_group present in the feed)
  FeaturedVideoCard ×1         (the most-viewed video in scope)
  VideoCarouselSection ×n      (one per tag) each with: title, viewAll→tagVideos
  VideoCarouselCard ×n         (thumb, title, meta, tap→play)
  FeedStatus ×1                (loading | error | empty)
  AppBottomNavBar ×1
```

### `carouselRows` — shipped today

```jsx
<VideosScreen>
  <AppTopbar mode="nameOnly" />
  <VideoCategoryTabs layout="scrollingPills" />

  <FeedStatus />
  <FeaturedVideoCard size="lg" />

  <VideoCarouselSection axis="horizontal">
    <SectionTitle /><ViewAllAction />
    <VideoCarouselCard size="md" />…
  </VideoCarouselSection>…

  <AppBottomNavBar />
</VideosScreen>
```

### `editorialStack`

No horizontal scrolling anywhere. Each tag is a vertical section of two large
cards plus a "view all" row. Slower to browse, far better for a tenant whose
content is long-form and whose members read titles.

```jsx
<VideosScreen>
  <AppTopbar mode="nameOnly" />
  <VideoCategoryTabs layout="scrollingPills" />

  <FeedStatus />
  <FeaturedVideoCard size="poster" bleed />

  <VideoCarouselSection axis="vertical" visible={2}>
    <SectionTitle />
    <VideoCarouselCard size="lg" />…
    <ViewAllAction layout="row" />
  </VideoCarouselSection>…

  <AppBottomNavBar />
</VideosScreen>
```

### `mosaic`

Featured occupies a double-width tile inside a mixed-size grid; tag titles become
inline band dividers. Highest content density of the five.

```jsx
<VideosScreen>
  <AppTopbar mode="nameOnly" />
  <VideoCategoryTabs layout="scrollingPills" pinned />

  <FeedStatus />
  <VideoCarouselSection layout="mosaic" columns={2}>
    <SectionTitle layout="inlineDivider" />
    <FeaturedVideoCard span={2} />
    <VideoCarouselCard size="tile" />…
    <ViewAllAction layout="tile" />
  </VideoCarouselSection>…

  <AppBottomNavBar />
</VideosScreen>
```

### `shortsColumn`

One vertical column of tall cards, tag name overlaid on each. Featured is simply
the first card, marked. The value that reads most like the platforms members
already use for this content.

```jsx
<VideosScreen>
  <AppTopbar mode="nameOnly" />
  <VideoCategoryTabs layout="topPills" />

  <FeedStatus />
  <VideoCarouselSection axis="vertical" layout="tall">
    <SectionTitle layout="overlay" />
    <FeaturedVideoCard size="tall" marked />
    <VideoCarouselCard size="tall" />…
    <ViewAllAction layout="inline" />
  </VideoCarouselSection>…

  <AppBottomNavBar />
</VideosScreen>
```

### `tagRail`

Tags move to a vertical left rail with scroll-spy; content is one column of medium
cards. Makes a large tag vocabulary navigable, which is exactly the case where the
horizontal pill strip fails.

```jsx
<VideosScreen>
  <AppTopbar mode="nameOnly" />
  <VideoCategoryTabs layout="verticalRail" scrollSpy />

  <FeedStatus />
  <FeaturedVideoCard size="md" pinned="columnTop" />

  <VideoCarouselSection axis="vertical" inset="rail">
    <SectionTitle layout="anchor" />
    <VideoCarouselCard size="md" />…
    <ViewAllAction layout="row" />
  </VideoCarouselSection>…

  <AppBottomNavBar />
</VideosScreen>
```

---

## 3.4 `rank_format`

Files: `features/profile/presentation/screens/profile_screen.dart` and the three
sections under `widgets/`.

```
INVARIANT
  AppTopbar ×1
  SparkleHero ×1               (top / accent / bottom copy — the streak statement)
  RankHeader ×1                (current rank name + belt)
  RatingGraph ×1               + TimeframeSelector ×1
  NextRankBadge ×1  NextRankTitle ×1  NextRankProgress ×1  NextRankProgressLabel ×1
  LevelUpVideosSection ×1      with header + cards
  SectionDivider ×n            (presentation only, count may vary)
  AppBottomNavBar ×1
```

Note: only **current** and **next** rank are available. Any variant implying rank
history would need data the screen does not fetch, and fails P14 on sight. That
ruled out an obvious-looking "journey timeline" value during authoring.

### `sparkleStack` — shipped today

```jsx
<ProfileScreen>
  <AppTopbar mode="nameOnly" />
  <SparkleHero size="lg" />

  <RankSummarySection>
    <RankHeader />
    <TimeframeSelector layout="pills" />
    <RatingGraph height="md" />
  </RankSummarySection>

  <SectionDivider />
  <NextRankSection layout="badgeLeft">
    <NextRankBadge /><NextRankTitle />
    <NextRankProgress /><NextRankProgressLabel />
  </NextRankSection>

  <SectionDivider />
  <LevelUpVideosSection axis="horizontal" />
  <AppBottomNavBar />
</ProfileScreen>
```

### `beltHero`

The belt becomes the full-width hero with the streak statement over it; next-rank
progress runs as an inline rail directly under the belt, so "where I am" and "what
is next" are one glance instead of two scroll positions.

```jsx
<ProfileScreen>
  <AppTopbar mode="nameOnly" />

  <RankSummarySection layout="hero">
    <RankHeader layout="beltBleed" />
    <SparkleHero size="md" position="overlay" />
    <NextRankProgress layout="rail" />
    <NextRankProgressLabel layout="inline" />
  </RankSummarySection>

  <NextRankSection layout="badgeInline">
    <NextRankBadge size="sm" /><NextRankTitle />
  </NextRankSection>

  <SectionDivider />
  <TimeframeSelector layout="pills" />
  <RatingGraph height="md" card />

  <SectionDivider />
  <LevelUpVideosSection axis="horizontal" />
  <AppBottomNavBar />
</ProfileScreen>
```

### `statTiles`

A 2×2 tile board opens the screen (streak, current rank, next-rank progress,
timeframe-scoped rating), graph as a wide band beneath. The most "dashboard" value
and the one that most suits a data-forward tenant.

```jsx
<ProfileScreen>
  <AppTopbar mode="nameOnly" />

  <TileBoard columns={2}>
    <SparkleHero size="tile" />
    <RankHeader layout="tile" />
    <NextRankSection layout="tile">
      <NextRankBadge size="sm" /><NextRankTitle />
      <NextRankProgress layout="ring" /><NextRankProgressLabel />
    </NextRankSection>
    <TimeframeSelector layout="tile" />
  </TileBoard>

  <RatingGraph height="lg" bleed />
  <SectionDivider />
  <LevelUpVideosSection axis="horizontal" />
  <AppBottomNavBar />
</ProfileScreen>
```

### `progressFirst`

Next-rank progress is promoted to a large arc with the belt inside it. Streak
demotes to a line. Optimised for the single question a graded-art member actually
opens this screen to ask.

```jsx
<ProfileScreen>
  <AppTopbar mode="nameOnly" />

  <NextRankSection layout="arc">
    <NextRankProgress layout="arc" size="xl" />
    <NextRankBadge size="lg" position="center" />
    <NextRankTitle align="center" />
    <NextRankProgressLabel align="center" />
  </NextRankSection>

  <SparkleHero size="line" />
  <RankHeader layout="row" />

  <SectionDivider />
  <TimeframeSelector layout="segmented" />
  <RatingGraph height="md" />

  <SectionDivider />
  <LevelUpVideosSection axis="horizontal" />
  <AppBottomNavBar />
</ProfileScreen>
```

### `splitRank`

Screen splits into now / next, with the graph as a collapsible strip on the seam.
The clearest information architecture of the five and the least visually eventful.

```jsx
<ProfileScreen>
  <AppTopbar mode="nameOnly" />

  <SplitPane half="top" label="now">
    <RankHeader layout="beltLeft" />
    <SparkleHero size="line" />
  </SplitPane>

  <RatingGraph height="sm" collapsible>
    <TimeframeSelector layout="inline" />
  </RatingGraph>

  <SplitPane half="bottom" label="next">
    <NextRankBadge size="md" /><NextRankTitle />
    <NextRankProgress layout="bar" /><NextRankProgressLabel />
  </SplitPane>

  <SectionDivider />
  <LevelUpVideosSection axis="horizontal" />
  <AppBottomNavBar />
</ProfileScreen>
```

---

## 3.5 `rewards_format`

Files: `features/rewards/presentation/screens/points_store_screen.dart`,
`widgets/store_grid/`, `widgets/reward_card/`.

```
INVARIANT
  AppTopbar ×1
  RewardsTabs ×1               (Points Store | My Rewards)
  PointsHeadline ×1            (the member's total points)
  RewardCard ×n  each carrying: image, priceLabel, title, pointsCost, redeem action
  RewardsLoadStatus ×1         (loading | error | empty)
  AppBottomNavBar ×1
```

### `cardGrid` — shipped today

```jsx
<PointsStoreScreen>
  <AppTopbar mode="nameOnly" />
  <RewardsTabs layout="twoUp" />
  <PointsHeadline size="lg" />

  <RewardsLoadStatus />
  <StoreGrid columns={2}>
    <RewardCard layout="imageTop">
      <RewardImageHero ratio="3:2"><RewardPriceTag corner="topRight" /></RewardImageHero>
      <RewardTitle lines={2} /><RewardPointsCost /><RedeemAction fullWidth />
    </RewardCard>…
  </StoreGrid>

  <AppBottomNavBar />
</PointsStoreScreen>
```

### `listRows`

Full-width rows, square thumb left, action right. Scans faster than a grid when
titles are long, which is the failure case the current 2-line clamp is papering
over.

```jsx
<PointsStoreScreen>
  <AppTopbar mode="nameOnly" />
  <RewardsTabs layout="twoUp" />
  <PointsHeadline size="lg" />

  <RewardsLoadStatus />
  <StoreGrid columns={1}>
    <RewardCard layout="thumbLeft" rule="hairline">
      <RewardImageHero ratio="1:1" size="sm"><RewardPriceTag layout="inline" /></RewardImageHero>
      <RewardTitle lines={1} /><RewardPointsCost layout="inline" />
      <RedeemAction layout="trailing" />
    </RewardCard>…
  </StoreGrid>

  <AppBottomNavBar />
</PointsStoreScreen>
```

### `posterDeck`

One large poster at a time in a snapping horizontal deck, points headline pinned
above, action full-width below the deck. Fewest rewards visible, strongest
individual reward.

```jsx
<PointsStoreScreen>
  <AppTopbar mode="nameOnly" />
  <RewardsTabs layout="segmented" />
  <PointsHeadline size="lg" pinned />

  <RewardsLoadStatus />
  <StoreGrid layout="deck" snap>
    <RewardCard layout="poster">
      <RewardImageHero ratio="4:5"><RewardPriceTag corner="topRight" /></RewardImageHero>
      <RewardTitle lines={2} align="center" /><RewardPointsCost size="lg" />
    </RewardCard>…
  </StoreGrid>
  <RedeemAction fullWidth position="belowDeck" />

  <AppBottomNavBar />
</PointsStoreScreen>
```

> `posterDeck` lifts the redeem action out of the card and pins it under the deck,
> so one action serves the focused card. The action count per screen changes even
> though the action count per reward does not. **This is the one variant in the
> library where the P14 multiset check needs a rule rather than a diff** — flagged
> for a ruling, see Open questions.

### `priceLadder`

Rewards grouped into cost bands, cheapest first, with the points headline as a
sticky affordability bar. Bands are derived from `pointsCost`, which is already on
the card, so nothing new is fetched.

```jsx
<PointsStoreScreen>
  <AppTopbar mode="nameOnly" />
  <RewardsTabs layout="twoUp" />
  <PointsHeadline size="md" pinned layout="affordanceBar" />

  <RewardsLoadStatus />
  <StoreGrid layout="banded" bandBy="pointsCost" columns={3}>
    <BandLabel />
    <RewardCard layout="tile" density="compact">
      <RewardImageHero ratio="1:1"><RewardPriceTag layout="corner" /></RewardImageHero>
      <RewardTitle lines={1} /><RewardPointsCost size="sm" /><RedeemAction size="sm" />
    </RewardCard>…
  </StoreGrid>

  <AppBottomNavBar />
</PointsStoreScreen>
```

### `storefrontHero`

Top reward is a full-bleed hero with its action on the image; the rest fall into a
2-up grid. The retail storefront pattern, and the strongest fit for a tenant
running a promoted item.

```jsx
<PointsStoreScreen>
  <AppTopbar mode="nameOnly" />
  <RewardsTabs layout="segmented" />

  <RewardsLoadStatus />
  <RewardCard layout="hero" bleed>
    <RewardImageHero ratio="16:9"><RewardPriceTag corner="topRight" /></RewardImageHero>
    <RewardTitle lines={1} overlay /><RewardPointsCost overlay />
    <RedeemAction overlay fullWidth />
  </RewardCard>

  <PointsHeadline size="md" layout="row" />
  <StoreGrid columns={2}>
    <RewardCard layout="imageTop" density="compact">…</RewardCard>…
  </StoreGrid>

  <AppBottomNavBar />
</PointsStoreScreen>
```

---

## 3.6 `class_format`

Files: `features/class_booking/presentation/screens/class_screen.dart` and its six
section widgets.

```
INVARIANT
  AppTopbar ×1 (showBackButton)
  ClassImageBanner ×1
  ClassMetaSection ×1          (title, time, date, duration, spots)
  ClassDetailsSection ×1       (description)
  ClassInstructorSection ×1    (name, photo, bio)
  ClassLocationSection ×1
  ClassReserveFooter ×1        (the single reserve action — never duplicated)
  SectionDivider ×n            (presentation only)
```

### `bannerStack` — shipped today

```jsx
<ClassScreen>
  <AppTopbar mode="nameOnly" showBackButton />
  <ClassImageBanner ratio="16:9" />

  <ClassMetaSection layout="stacked" />
  <SectionDivider />
  <ClassDetailsSection />
  <SectionDivider />
  <ClassInstructorSection layout="avatarLeft" />
  <SectionDivider />
  <ClassLocationSection />

  <ClassReserveFooter position="pinned" />
</ClassScreen>
```

### `overlayHero`

Meta rides the bottom of a taller image under a scrim; instructor is promoted
above the description, because for a combat gym the coach is the reason to book.

```jsx
<ClassScreen>
  <AppTopbar mode="nameOnly" showBackButton overlay />
  <ClassImageBanner ratio="4:5" scrim>
    <ClassMetaSection layout="overlay" />
  </ClassImageBanner>

  <ClassInstructorSection layout="avatarLeft" />
  <SectionDivider />
  <ClassDetailsSection />
  <SectionDivider />
  <ClassLocationSection />

  <ClassReserveFooter position="pinned" />
</ClassScreen>
```

### `detailSheet`

The image is a fixed backdrop; content rises as a draggable sheet over it and the
reserve action sits at the top of the sheet, in thumb reach on the way down rather
than at the end of a scroll.

```jsx
<ClassScreen>
  <AppTopbar mode="nameOnly" showBackButton overlay />
  <ClassImageBanner layout="backdrop" fill />

  <Sheet draggable initial="60%">
    <ClassReserveFooter position="sheetTop" />
    <ClassMetaSection layout="stacked" />
    <SectionDivider />
    <ClassDetailsSection />
    <SectionDivider />
    <ClassInstructorSection layout="avatarLeft" />
    <SectionDivider />
    <ClassLocationSection />
  </Sheet>
</ClassScreen>
```

### `sectionTabs`

Banner and meta stay fixed; details / instructor / location become three tabs in
one swipeable pane. Removes all scrolling from the decision, at the cost of hiding
two thirds of the content behind a tap.

```jsx
<ClassScreen>
  <AppTopbar mode="nameOnly" showBackButton />
  <ClassImageBanner ratio="16:9" />
  <ClassMetaSection layout="stacked" pinned />

  <TabPane swipeable>
    <ClassDetailsSection tab="details" />
    <ClassInstructorSection tab="instructor" layout="avatarTop" />
    <ClassLocationSection tab="location" />
  </TabPane>

  <ClassReserveFooter position="pinned" />
</ClassScreen>
```

### `specBrief`

No banner. A small inline thumb, then a dense two-column spec table, description
last, action inline at the end of content. The value for a member who has taken
this class fifty times and wants the time and the mat, not the poster.

```jsx
<ClassScreen>
  <AppTopbar mode="nameOnly" showBackButton />

  <ClassMetaSection layout="specTable" columns={2}>
    <ClassImageBanner ratio="1:1" size="thumb" position="inline" />
  </ClassMetaSection>

  <SectionDivider />
  <ClassInstructorSection layout="row" density="compact" />
  <ClassLocationSection layout="row" density="compact" />
  <SectionDivider />
  <ClassDetailsSection />

  <ClassReserveFooter position="inline" />
</ClassScreen>
```

---

## 3.7 `celebration_format`

Files: `shared/widgets/post_class/post_class_scaffold.dart` and the five bodies
under `features/stats/presentation/widgets/`.

This enum applies to **all five** post-class cards (streak, wins, points, rewards,
rank). The body slot differs per card; the arrangement around it does not.

```
INVARIANT
  CelebrationHeader ×0..1      (present where the screen passes one)
  CloseAction ×1
  HeroIllustration ×1          (the card's image slot)
  StatValue ×1                 (the count-up figure)
  StatCaption ×1
  SupportingDetail ×0..1       (e.g. StreakWeekStrip, RewardsCarousel)
  PrimaryCta ×1
```

### `centerHero` — shipped today

```jsx
<PostClassScaffold>
  <CloseAction corner="topRight" />
  <CelebrationHeader />
  <Stage align="center">
    <HeroIllustration size="lg" />
    <StatValue size="display" />
    <StatCaption />
    <SupportingDetail />
  </Stage>
  <PrimaryCta fullWidth position="pinned" />
</PostClassScaffold>
```

### `figureTop`

The number is huge and top-aligned; the illustration bleeds off the bottom edge
behind the CTA. Puts the earned figure at the top of the read, which is where the
eye lands first on a screen opened at arm's length.

```jsx
<PostClassScaffold>
  <CloseAction corner="topRight" />
  <CelebrationHeader />
  <Stage align="topLeading">
    <StatValue size="displayXl" />
    <StatCaption />
    <SupportingDetail />
    <HeroIllustration size="xl" bleed="bottom" behind />
  </Stage>
  <PrimaryCta fullWidth position="pinned" />
</PostClassScaffold>
```

### `cardReveal`

The stat sits on a raised card centred in the canvas with the illustration
breaking over the card's top edge. The most "collectible" of the five and the one
that best suits a tenant leaning on rewards.

```jsx
<PostClassScaffold>
  <CloseAction corner="topRight" />
  <CelebrationHeader />
  <Stage align="center">
    <Card elevated>
      <HeroIllustration size="md" position="breakTop" />
      <StatValue size="display" />
      <StatCaption />
      <SupportingDetail />
    </Card>
  </Stage>
  <PrimaryCta fullWidth position="pinned" />
</PostClassScaffold>
```

### `splitBand`

Canvas splits into an illustration band over a plain lower half carrying the stat,
caption and action. The calmest value, and the only one that survives a very busy
tenant illustration without the figure losing contrast.

```jsx
<PostClassScaffold>
  <CloseAction corner="topRight" overlay />
  <Band half="top" fill>
    <HeroIllustration size="lg" />
    <CelebrationHeader position="overlay" />
  </Band>
  <Band half="bottom" align="center">
    <StatValue size="display" />
    <StatCaption />
    <SupportingDetail />
    <PrimaryCta fullWidth />
  </Band>
</PostClassScaffold>
```

### `fullBleed`

Illustration fills the screen; stat, caption and action stack in the lower third
over a scrim. The highest-impact value and the most dependent on illustration
quality, which makes it the riskiest default for a tenant whose generated imagery
is weak.

```jsx
<PostClassScaffold>
  <CloseAction corner="topRight" overlay />
  <HeroIllustration size="fill" bleed="all" />
  <Stage align="bottom" scrim>
    <CelebrationHeader />
    <StatValue size="display" />
    <StatCaption />
    <SupportingDetail density="compact" />
    <PrimaryCta fullWidth />
  </Stage>
</PostClassScaffold>
```

---

# Motion enums

Motion is a **token**, not a layout, so it stays on the pipeline side of the
P13b boundary (assets are data, layout is code) and remains orthogonal to every
layout enum above. A tenant's motion choice must not be able to break any
arrangement.

The shape is two layers: one personality that resolves the whole set, plus
per-surface overrides for the surfaces that carry brand weight.

## 4.1 `motion_personality`

Resolves the timing set. Everything else inherits from it unless explicitly
overridden.

| value | element duration | curve | stagger | count-up | particle count |
|---|---|---|---|---|---|
| `calm` | 220ms | easeOutSine | 40ms | 900ms | 0 |
| `standard` *(shipped)* | 260ms | easeOutQuart | 90ms | 1400ms | 12 |
| `hype` | 200ms | easeOutExpo | 55ms | 1100ms | 20 |
| `cinematic` | 420ms | easeOutQuint | 140ms | 2000ms | 8 |

Shipped values come from `shared/widgets/animation/celebration_timings.dart`
(`revealDuration` 260ms, `revealStagger` 90ms, `countUpDuration` 1400ms,
`sparkleWindow` 620ms).

**`hype` gets its energy from density, not from bounce.** No value in this enum
uses an overshoot or elastic curve. `PRODUCT.md` bans bounce outright and the
existing motion law is ease-out only; a "hype" that reached for `easeOutBack`
would be a brand change smuggled in as a token.

> [!warning] `cinematic` breaks the ≤300ms per-element ceiling.
> `MobileApp/CLAUDE.md` and `PRODUCT.md` both state ease-out, no bounce, ≤300ms.
> `cinematic` at 420ms is a deliberate exception that needs a ruling: either the
> ceiling becomes a per-personality token rather than an app-wide law, or
> `cinematic` gets capped at 300ms and finds its weight in stagger alone. See
> Open questions.

## 4.2 Per-surface overrides

### `celebration_intro`

The one-shot intro that plays before a post-class card settles. Current
implementation is the streak orbit in
`features/stats/presentation/widgets/streak/streak_body.dart`.

| value | behaviour |
|---|---|
| `orbit` *(shipped)* | Icon pops at centre, a rotating ring of particles expands outward then collapses, icon exits into the stat cascade. |
| `burst` | Particles fire outward from the icon once and fade in place. No ring, no rotation. Shortest of the four. |
| `rise` | Icon rises from below the fold with a trailing blur, settles, then the stats cascade. No particles. |
| `flipCount` | Icon flips in on the Y axis; the count-up starts mid-flip so the figure is already moving when the icon lands. |
| `none` | Card arrives settled. Stats still cascade via `reveal_style`. |

### `reveal_style`

The per-element entrance used by `StaggeredReveal` and `ScaleReveal` everywhere
in the celebration stack.

| value | behaviour |
|---|---|
| `fadeUp` *(shipped)* | Opacity 0→1 with a 12px upward translate. `StaggeredReveal` today. |
| `scalePop` | Opacity 0→1 with scale 0.5→1. `ScaleReveal` today, promoted to the default entrance. |
| `slideIn` | Horizontal translate from the leading edge, opacity held near 1. |
| `maskWipe` | Element is revealed by a clip-path wipe along its own axis. No transform. |
| `none` | Elements are present at full opacity. Stagger still governs order of appearance for the count-up. |

### `loader_style`

The waiting state. Current implementation is
`shared/widgets/animation/loading_dots.dart`.

| value | behaviour |
|---|---|
| `dots` *(shipped)* | Three brand dots in a travelling bounce wave, 1100ms cycle. |
| `pulseRing` | A single ring scales out and fades, repeating. |
| `barSweep` | An indeterminate bar sweeps its track. |
| `logoBreathe` | The tenant mark scales between 0.94 and 1.0 on a slow cycle. The most white-label-native of the four, since the mark is already a customization slot. |

### `transition_style`

Screen-to-screen motion. Currently unimplemented: the app uses Flutter's default
route transition everywhere, so this enum's first job is to make an existing
default explicit.

| value | behaviour |
|---|---|
| `fade` | Cross-fade, no translation. |
| `sharedAxis` | Paired slide plus fade along the navigation axis (Material's shared-axis pattern). |
| `cardStack` | Incoming screen rises over the outgoing one, which recedes slightly. |
| `none` | Instant cut. |

### `count_up_style`

How an earned figure arrives. Current implementation is the odometer reel in
`shared/widgets/animation/count_up_text.dart`.

| value | behaviour |
|---|---|
| `odometer` *(shipped)* | Per-digit vertical reels, steep ease-out-expo, digits land right to left. |
| `ticker` | Whole number re-renders through intermediate values, no per-digit motion. |
| `sweepArc` | Figure holds while an arc sweeps to the value beneath it, then both settle. |
| `instant` | Final value on arrival. Still respects `reveal_style` for its entrance. |

### `sparkle_style` — proposed, not in the approved set

Not in the five surfaces confirmed for this pass. Proposed because `SparkleBurst`
and `SparkleHero` are a real, separately-branded surface in this app
(`shared/widgets/sparkle_hero/`, `shared/widgets/animation/sparkle_burst.dart`),
and `motion_personality` currently reaches them only through particle count.

| value | behaviour |
|---|---|
| `scatter` *(shipped)* | Fixed radial scatter of 12 particles fading in over a 620ms window. |
| `orbit` | Particles hold a slow orbit around the hero rather than fading in place. |
| `trail` | Particles emit along the stat's own baseline as the count-up runs. |
| `none` | No decorative particles. `motion_personality` particle count is ignored. |

Needs a ruling before it enters the manifest.

---

# 5. Wiring it into the existing engine

The layout and motion enums are new slot *kinds* on the manifest in
`MobileApp/lib/core/app_slots.dart`, which today declares colours, images, fonts,
texts, and icons. The shape follows the file's existing convention exactly: an
explicit `static const` id plus one line in the matching `expected*` list, with a
matching declaration in the service's `apps/<app>/app.yaml`.

```dart
// ---- Layout slots ----
static const String appShellFormat = 'app_shell_format';
static const String homeFormat = 'home_format';
static const String videosFormat = 'videos_format';
static const String rankFormat = 'rank_format';
static const String rewardsFormat = 'rewards_format';
static const String classFormat = 'class_format';
static const String celebrationFormat = 'celebration_format';

static const List<String> expectedLayouts = [
  appShellFormat, homeFormat, videosFormat, rankFormat,
  rewardsFormat, classFormat, celebrationFormat,
];

// ---- Motion slots ----
static const String motionPersonality = 'motion_personality';
static const String celebrationIntro = 'celebration_intro';
static const String revealStyle = 'reveal_style';
static const String loaderStyle = 'loader_style';
static const String transitionStyle = 'transition_style';
static const String countUpStyle = 'count_up_style';

static const List<String> expectedMotion = [
  motionPersonality, celebrationIntro, revealStyle,
  loaderStyle, transitionStyle, countUpStyle,
];
```

Consumption mirrors the existing accessors (`ThemeColor.color`, `ThemeImage.image`,
`ThemeFont.style`, `ThemeText.value`, `ThemeIcon.widget`): a `ThemeLayout.value`
and a `ThemeMotion.value` returning the resolved enum with the shipped value as
the fallback, so an unbranded build and any tenant missing the slot both render
exactly what ships today.

**Not written yet.** This section is the proposed shape, not applied code. No file
under `lib/` is changed by this document.

---

# 6. Open questions

1. **Does `posterDeck` pass the P14 gate?** It lifts the redeem action out of the
   card and pins one action under the deck. Per-reward action count is unchanged;
   per-screen action count is not. Either the gate counts actions per data row
   rather than per screen, or the value is cut. This is the first real test of
   whether the multiset rule needs nuance, which makes it worth resolving before
   the gate is built rather than after.

2. **Does `cinematic` get to break the 300ms ceiling?** Either the ceiling becomes
   a per-personality token, or `cinematic` caps at 300ms and finds its weight in
   stagger and count-up length alone. The second keeps one app-wide motion law and
   is the smaller change.

3. **Is `sparkle_style` in or out?** It is a real branded surface and the
   personality enum currently reaches it only by particle count. Adding it makes
   six surface enums instead of five.

4. **Should `markOnly` and `nextUpHero` ship as offerable defaults?** Both hide
   something a tenant may specifically want visible: the gym name, and the class
   thumbnails. Both hold the invariant. Neither is obviously safe as a default.

5. **How many values per screen is the right library size?** Five per screen is
   what this pass produced. T10 says human review is the throughput ceiling, so
   the number of values is a cost decision, not a design one, and it should be set
   deliberately rather than by whatever a generation run happens to emit.

6. **Do the two home bodies stay two bodies?** `HomeNotBookedBody` and
   `HomeBookedBody` are near-identical trees differing by one card. Every layout
   value has to be authored twice under the current split. Collapsing them to one
   body with a nullable card would halve the layout authoring cost, and it is a
   pre-existing duplication rather than something this work introduced.

---

## Companion preview

`MobileApp/docs/layout_formats_preview.html` renders every value above as a
wireframe specimen, with the motion enums as live loops.
