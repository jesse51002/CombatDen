# 03 — Widget hygiene

Lower-priority widget-placement / shared-vs-feature consolidations. Not bugs. Don't fix until a clean window — but worth documenting so the next refactor pass picks them up.

## Shared widgets to extract from FlutterCRM

CLAUDE.md says: "Before building a new shared widget, also check `../FlutterCRM/lib/shared/widgets/`. If a version of the pattern exists there (e.g. `subtitle_section.dart`, `section_card.dart`), copy and adapt it rather than building from scratch."

The MobileApp has **multiple `*_section.dart` widgets** that each reimplement the title+content pattern inline. Examples:
- `lib/features/class_booking/presentation/widgets/class_meta_section.dart`
- `lib/features/class_booking/presentation/widgets/class_details_section.dart`
- `lib/features/class_booking/presentation/widgets/class_instructor_section.dart`
- `lib/features/class_booking/presentation/widgets/class_location_section.dart`
- `lib/features/photo_verification/presentation/widgets/benefits/benefits_list.dart`
- `lib/features/rewards/presentation/widgets/summary/recommended_drill_section.dart`
- `lib/features/profile/presentation/widgets/rank_summary/rank_summary_section.dart`

Each one builds its own `Column(spacing: spacingLarge, children: [Text(title, style: h2/h3), content])` from scratch. FlutterCRM has a `subtitle_section.dart` (and likely `section_card.dart`) that does this generically. If those widgets exist there, copy them into `lib/shared/widgets/` and have the section files use them.

**Bonus**: this would also fix the same-level cascade inconsistency in `class_screen._Body` from `01_real_bugs.md` — every section using a shared `SubtitleSection` widget would gap identically by construction.

## Genuinely-shared widget candidates

### `lib/features/photo_verification/presentation/widgets/selfie_circle.dart`

A circular `ClipOval` over an `Image.asset`. Used in `photo_verify_start_screen.dart`, `photo_verify_active_screen.dart`, and `photo_verify_review_screen.dart` — all 3 photo-verification screens.

Currently lives in the feature folder. It's a generic primitive (circular avatar / image clip) and would have value if any future screen needs the same pattern (profile avatar, session player thumbnail, etc.). **Move to `lib/shared/widgets/` if/when a second feature needs it.** No urgency right now — used in 3 closely-related screens.

### Streak label pattern

Two implementations of "streak icon + text" in a row:
- `lib/features/profile/presentation/widgets/streak_banner/streak_banner.dart` — large 23×30 icon + h2-styled "You're on a streak" headline.
- `lib/features/home/presentation/widgets/upcoming_sessions/upcoming_sessions_card.dart:60` (`_StreakFooter`) — small 12×15 icon + `p`-styled "You're on a $weeks week streak!" footnote.

Both load `assets/images/icon_streak.png`. Different sizes / typography but the same conceptual unit. Could become a `StreakLabel({size, headline})` shared widget. Marginal — leave until there's a third occurrence.

### Two-tab segmented strip

- `lib/features/rewards/presentation/widgets/rewards_tabs.dart` — Points Store / My Rewards.
- `lib/features/home/presentation/widgets/class_schedule/date_tab.dart` — date pills under class schedule (different shape but same active-vs-inactive treatment).

Different enough that unification would need careful generalization. Skip unless a third tab strip shows up.

### Media preview cards

`lib/features/rewards/presentation/widgets/summary/youtube_player_card.dart` plus its siblings (`watch_on_youtube_badge.dart`, `youtube_play_button.dart`) form a generic "video preview with play overlay + branding badge" card. They're tied to summary mock data right now but the pattern itself is generic. Move to `lib/shared/widgets/media_preview/` if a second consumer appears.

---

## What was checked and dismissed

The original audit subagent flagged a few duplicates that turned out not to hold up:

- **`video_recc_header.dart` ≈ `_SectionHeader` inside `video_carousel_section.dart`**: not duplicates. The first is a modal close header (centered title + X button on right). The second is a section header (title left + "view all" link right). Different purposes, different layouts. Leave as-is.
- **`session_summary_row.dart` ≈ `class_list_item.dart`**: `session_summary_row.dart` does not exist in the current codebase. Likely was deleted in an earlier refactor. No action.
- **Splitting `mock_stats.dart`**: the user does not want to split this. Tightly-related model classes are easier to read together. Leave as-is.
