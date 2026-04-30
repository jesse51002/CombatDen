# 01 — Real bugs

High-confidence fix list. Every entry below was verified by reading the cited file in context. Each entry: `path:line` — quote — rule cited — fix.

---

## Theming

### `lib/shared/widgets/buttons/app_outline_button.dart:38`

```dart
final radius = borderRadius ?? 100;
```

- **Rule** ("Theming System"): "NEVER hardcode … radius … Use `DesignConstants.radius*`."
- **Fix**: Replace `100` with the closest existing constant. The widget is documented as a "fully-rounded pill" — pick `DesignConstants.radiusBig`, or escalate that the tokens lack a true "pill" radius and a new one is needed.

---

## Spacing

### `lib/features/class_booking/presentation/widgets/class_reserve_footer.dart:14-15`

```dart
return Padding(
  padding: EdgeInsets.only(top: DesignConstants.spacingBig),
  child: Column( ... ),
);
```

- **Rule** ("Screen Layout & Spacing → Spacing rules"): "Never use `Padding` to create a gap between sibling widgets — gaps belong to the parent's `spacing:` parameter."
- **Context**: This widget is only used at `lib/features/class_booking/presentation/screens/class_screen.dart:58` as the last sibling in the screen's outer `Column` (which has no `spacing:`). The inner top-padding is faking a sibling gap.
- **Fix**: Remove the wrapping `Padding`; add an explicit `spacing:` to the parent `Column` in `class_screen.dart`, or add a `SectionDivider`-style separator. Single-caller widget, safe to refactor.

### `lib/features/videos/presentation/widgets/video_recc_header.dart:20-21`

```dart
return Padding(
  padding: EdgeInsets.only(top: DesignConstants.spacingBig),
  child: Stack( ... ),
);
```

- **Rule**: same as above (sibling gap belongs to parent's `spacing:`).
- **Context**: Used in 2 places — `video_recc_screen.dart:29` and `summary_screen.dart:22`. Verify both call sites before fixing; both parents likely need `spacing:` instead.
- **Fix**: Remove the wrapping `Padding`; ensure both callers' parent `Column`s use `spacing:`.

### `lib/features/profile/presentation/screens/profile_screen.dart:25`

```dart
padding: EdgeInsets.only(bottom: DesignConstants.paddingBig * 2),
```

- **Rule** ("Theming System"): "NEVER hardcode spacing, padding…" — `paddingBig * 2` is magic arithmetic, not a token.
- **Fix**: Either pick a real token that fits (audit `DesignConstants.padding*` for `64`), or extract a `_kBottomScrollPadding` const at the top of the file with a comment explaining why the pad is needed (likely to clear the bottom nav). If no token matches, escalate to add one to `DesignConstants`.

### `lib/shared/widgets/photo_verification_card/photo_verification_card.dart:53`

```dart
Expanded(
  flex: 4,
  child: Column(
    ...
    spacing: DesignConstants.spacingLarge,  // <-- line 53
    children: [
      Text('Earn Rewards from Gyming', style: DesignConstants.h3),
      Text('Complete photo verification ...', style: ...),
    ],
  ),
),
```

- **Rule** ("Section Structure & Gap Hierarchy"): "Innermost related items use `spacingSmall` / `spacingTiny`. Title and supporting description are tightly paired — the gap between them should be smaller than the gap between the row block and the button."
- **Verified against Figma** `home page booked` (`auxEZmrWWZ61mNnrFQxVg0`, node `47:101`). The design shows a tight title→description gap and a moderate gap to the "Complete Photo Verification" button. Current code uses `spacingLarge` for both.
- **Fix**: Change the inner Column's `spacing:` from `spacingLarge` to `spacingSmall` (or `spacingTiny` — pull up the Figma frame and pick whichever fits closer). Outer Column at line 23 already uses `spacingLarge` correctly.

### Same-level cascade inconsistencies (4 sites)

The cascade rule allows large→medium→small as you go deeper, but **siblings at the same level must use the same gap**. These four screens have title→content gaps that disagree across siblings:

#### `lib/features/class_booking/presentation/screens/class_screen.dart` `_Body` (line 86-99)

The four sections under `_Body` have inconsistent inner-Column `spacing:` values:
- `ClassMetaSection` — `spacingLarge` (`class_meta_section.dart:17`)
- `ClassDetailsSection` — `spacingMedium` (`class_details_section.dart:15`)
- `ClassInstructorSection` — `spacingMedium` (`class_instructor_section.dart:16`)
- `ClassLocationSection` — `spacingMedium` (`class_location_section.dart:16`)

**Fix**: Pick one (likely `spacingMedium` since 3 of 4 already use it) and align all four. Re-check against Figma `Class Screen` (node `51:21`) before changing.

#### `lib/features/videos/presentation/widgets/video_carousel_section.dart:40` vs `lib/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart:37`

```dart
// video_carousel_section.dart:40
Row(
  spacing: DesignConstants.spacingLarge,
  children: [for (final v in videos) VideoCarouselCard(...)],
),

// level_up_videos_section.dart:37
Row(
  spacing: DesignConstants.spacingMedium,
  children: [for (final video in videos) SizedBox(width: ..., child: VideoCard(...))],
),
```

Two video carousels in the app use different inter-card gaps (16 vs 8). Visible inconsistency.
**Fix**: Align both. Verify against Figma which is correct.

#### `lib/features/stats/presentation/widgets/rewards/rewards_body.dart:22 vs :44`

```dart
// First Column (title + subtitle), line 22
Column(
  spacing: DesignConstants.spacingMedium,
  children: [Text(stats.title, ...), Text(stats.subtitle, ...)],
),

// Third Column (name + discountLabel), line 44
Column(
  spacing: DesignConstants.spacingLarge,
  children: [Text(featured.name, ...), Text(featured.discountLabel, ...)],
),
```

Two title+supporting-text pairs at the same hierarchy level use different gaps (8 vs 16). The hierarchy reads inconsistent.
**Fix**: Pick one and align. Verify against Figma `Rewards` (node `131:64`).

---

## Scaffold

### `lib/features/home/presentation/screens/home_screen.dart:31`

```dart
return Scaffold(
  backgroundColor: DesignConstants.backgroundColor,
  body: SafeArea(
    bottom: false,
    child: Column(
      children: [
        Expanded(child: PageView(...)),
        const AppBottomNavBar(selected: AppBottomNavTab.home),
      ],
    ),
  ),
);
```

- **Rule** ("Screen frame"): "Use `AppScreenScaffold` for every screen. Don't hand-roll `Scaffold` + `SafeArea` + `Padding` per screen."
- **Fix**: Migrate to `AppScreenScaffold(horizontalPadding: AppScreenHorizontalPadding.none, bottomNav: AppBottomNavBar(selected: AppBottomNavTab.home), child: PageView(...))`.

### `lib/shared/widgets/post_class/post_class_scaffold.dart:30`

```dart
return Scaffold(
  backgroundColor: DesignConstants.backgroundColor,
  body: SafeArea(
    child: Stack(...)
  ),
);
```

- **Rule**: same as above — parallel scaffold abstraction.
- **Context**: Consumed by 5 post-class screens (`streak_screen`, `rank_screen`, `points_screen`, `rewards_card_screen`, `wins_screen`).
- **Fix**: Refactor `PostClassScaffold` to **compose** `AppScreenScaffold` internally rather than building its own `Scaffold`. The 5 caller screens stay unchanged. Stack overlay (close button) and bottom CTA become children of the inner scaffold's body.

---

## File organization

### `lib/features/home/presentation/screens/home_booked_body.dart` and `home_not_booked_body.dart`

These are not screens — they are `PageView` children swapped by `HomeScreen`. They live in `screens/` only by historical accident.

- **Rule** ("Project Structure"): screens go in `presentation/screens/`; widgets go in `presentation/widgets/`.
- **Fix**: Move both files out of `screens/` into `presentation/widgets/home_body/` (or `widgets/` flat). Update imports in `home_screen.dart`.

---

## Dependencies

### `pubspec.yaml:36`

```yaml
cupertino_icons: ^1.0.8
```

- **Rule** ("Dependencies"): "intentionally minimal — `google_fonts` and `material_symbols_icons` only." `cupertino_icons` is the Flutter-template default and is not used anywhere in the codebase (icons are exclusively `Symbols.*_sharp`).
- **Fix**: `flutter pub remove cupertino_icons`.

---

## Line length

### `lib/features/home/presentation/widgets/class_schedule/class_list_item.dart:88`

```dart
        if (classData.attending != null) _BookedCount(count: classData.attending!),
```

- **Rule** ("Dart Standards → Formatting"): "Max 80 characters per line." This line is 82.
- **Fix**: Reformat to multi-line:

```dart
        if (classData.attending != null)
          _BookedCount(count: classData.attending!),
```
