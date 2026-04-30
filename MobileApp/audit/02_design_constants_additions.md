# 02 — DesignConstants additions

These are inline `width` / `height` literals on non-image widgets that the user agreed should become new tokens in `DesignConstants` rather than escalated. Each one is a real magic number in styled chrome (pills, tabs, button backgrounds).

## Important: mirror to FlutterCRM

`MobileApp/lib/core/constants/design_constants.dart` is **byte-identical** to `FlutterCRM/lib/core/constants/design_constants.dart` (verified). Per CLAUDE.md: "Keep the two files byte-for-byte identical until they are extracted into a shared package. If a token is added in one repo, mirror it to the other in the same change."

So every token added below must be added to both files in the same commit.

## Proposed token names

These are starting suggestions — pick whichever names match the existing T-shirt scale conventions in `DesignConstants`.

| Use | Current literal | Proposed token | Notes |
|---|---|---|---|
| Small pill height (number badges) | `24` | `pillHeightSm` | Maps to `DeltaPill` |
| Medium pill height (timeframe selector) | `30` | `pillHeightMd` | Maps to `TimeframePill` |
| Fixed tab item width | `120` | `tabWidthFixed` or carve to `Expanded` | Maps to `_RewardsTabItem` |
| Fixed-width gutter (label column in row) | `70` | `gutterWidthMd` | Maps to `UpcomingSessionRow` left gutter |
| Media-overlay button background (w×h) | `68 × 48` | `playButtonWidth` / `playButtonHeight` (or treat as image-bound and inline) | Maps to `YoutubePlayButton` |

Decide whether the `120`-wide tab should become a token or be replaced with `Expanded`/`Flexible` so the two tabs share width — that's a layout fix, not a token addition.

---

## Sites to update once the tokens land

### `lib/shared/widgets/pills/delta_pill.dart:15`

```dart
return Container(
  height: 24,
  padding: EdgeInsets.symmetric(
    horizontal: DesignConstants.spacingMedium,
  ),
  ...
);
```

Replace `24` with `DesignConstants.pillHeightSm`.

### `lib/shared/widgets/pills/timeframe_pill.dart:23`

```dart
child: Container(
  height: 30,
  padding: EdgeInsets.symmetric(
    horizontal: DesignConstants.screenHorizontalPadding,
  ),
  ...
),
```

Replace `30` with `DesignConstants.pillHeightMd`.

### `lib/features/rewards/presentation/widgets/rewards_tabs.dart:79`

```dart
child: Container(
  width: 120,
  padding: EdgeInsets.only(bottom: DesignConstants.spacingMedium),
  ...
),
```

Either replace `120` with a new `tabWidthFixed` token, or restructure to `Row(children: [Expanded(child: tab1), Expanded(child: tab2)])` so each tab takes half the width without a magic number.

### `lib/features/home/presentation/widgets/upcoming_sessions/upcoming_session_row.dart:23`

```dart
SizedBox(
  width: 70,
  child: Column(
    ...
    children: [
      Text(session.dayLabel, style: DesignConstants.p),
      Text(session.time, ...),
    ],
  ),
),
```

This is a fixed-width gutter for the day/time label so subsequent rows align vertically. Replace `70` with `DesignConstants.gutterWidthMd` (or whatever the chosen name is).

### `lib/features/rewards/presentation/widgets/summary/youtube_play_button.dart:12-13`

```dart
return Container(
  width: 68,
  height: 48,
  decoration: BoxDecoration(
    color: DesignConstants.badRed,
    borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
  ),
  ...
);
```

This is a media-overlay button background — the play arrow icon sits centered inside it. Two options:
1. Treat as image-bound and inline (the play button looks like an image overlay even though it's a Container). Defensible.
2. Add `playButtonWidth = 68` and `playButtonHeight = 48` tokens.

Pick whichever feels less weird. Option 1 is more honest about what this widget actually is (a YouTube-style play badge).
