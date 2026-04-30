# 04 — CLAUDE.md updates

Three small documentation changes to `MobileApp/CLAUDE.md`. These are not code fixes — they bless current patterns that the audit flagged as edge cases against an over-strict reading of the existing rules. The user explicitly approved each change.

---

## 1. Bless `_kFoo` for non-image layout math

**Where**: in the "Theming System" section, the bullet about image dimensions:

> **Image dimensions ARE allowed inline.** `Image.asset(width:, height:)`, asset-bound `SizedBox` constraints, and layout `aspectRatio:` are per-asset Figma values — they're not fungible design tokens, and there is no `imageSize*` catalog. Type the literal pixel value (or hoist it to a private `_kFoo` const at the top of the file when reused). Same for one-off `Positioned(left:/top:/...)` math when laying out an image overlay.

**Add a follow-up bullet:**

> **`_kFoo` private file-scoped constants are also allowed for scroll-position math, sliver / pinned-header heights, and pure layout arithmetic that has no `DesignConstants` equivalent.** Examples: `_kTopbarHeight = 268`, `_kDateRowHeight = 50`, `_kCardWidth = 258`. The carve-out is for *layout math that is intrinsically per-screen and not a fungible design token*. If the same number appears across multiple screens or controls, it's not a `_k` candidate — escalate to add a `DesignConstants` token instead.

**Why**: 8 sites in the codebase already use this pattern (`home_booked_body.dart`, `home_not_booked_body.dart`, `date_row.dart`, `app_bottom_nav_bar.dart`, `level_up_videos_section.dart`, `video_carousel_card.dart`). The current rule technically only blesses the pattern for image dimensions, so each site is a gray-area violation. Either change the doc or refactor 8 sites — the doc change is the right call.

---

## 2. Carve out import lines from the 80-char limit

**Where**: in the "Dart Standards → Formatting" section:

> Max 80 characters per line.
> `dart format` for consistent formatting.
> Trailing commas on multi-line widget trees for clean diffs.

**Update to:**

> Max 80 characters per line **for body code**. Package imports are exempt — Dart's formatter doesn't break import lines, and renaming folders to fit a column limit isn't worth it.
> `dart format` for consistent formatting.
> Trailing commas on multi-line widget trees for clean diffs.

**Why**: 102 lines across 41 files exceed 80 chars, and every one of them is a deep `package:mobile_app/...` import (e.g. `package:mobile_app/features/photo_verification/presentation/widgets/benefits/benefit_row.dart`). `dart format` won't break these. The only "fix" is to flatten the folder structure, which would hurt the deep-module-tree principle the rest of CLAUDE.md endorses. Carve them out.

---

## 3. Document `core/navigation/`

**Where**: in the "Project Structure" section:

```
lib/
├── main.dart
├── core/
│   └── constants/
│       └── design_constants.dart   # IMMUTABLE — copied from FlutterCRM
├── features/
│   └── <feature>/
│       ├── data/
│       │   └── mock_<thing>.dart   # hardcoded prototype data
│       └── presentation/
│           ├── screens/
│           └── widgets/
└── shared/
    ├── themes/
    │   └── app_theme.dart
    └── widgets/                    # cross-feature reusables
```

**Update to:**

```
lib/
├── main.dart
├── core/
│   ├── constants/
│   │   └── design_constants.dart   # IMMUTABLE — copied from FlutterCRM
│   └── navigation/
│       └── app_routes.dart         # named-route constants + builder map
├── features/
│   └── <feature>/
│       ├── data/
│       │   └── mock_<thing>.dart   # hardcoded prototype data
│       └── presentation/
│           ├── screens/
│           └── widgets/
└── shared/
    ├── themes/
    │   └── app_theme.dart
    └── widgets/                    # cross-feature reusables
```

**Why**: `lib/core/navigation/app_routes.dart` exists and is wired into `main.dart`'s routing table, but it isn't in the documented project tree. New contributors reading CLAUDE.md would think it's misplaced. Document it.
