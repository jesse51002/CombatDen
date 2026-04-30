# MobileApp Coding Standards Audit

Audit of `/var/home/jm/Documents/CombatDen/codebase/MobileApp/` against `MobileApp/CLAUDE.md`. **No code changes were made** — this folder describes findings only.

## Headline result

The codebase is in **very good shape**. `flutter analyze` is clean. Zero violations on icons, colors, fonts, imports, dead code, `NetworkImage`, state-management leakage, or new-dependency leakage. Real findings concentrate in five areas, captured in the four files below.

| File | Severity | What's in it |
|---|---|---|
| [`01_real_bugs.md`](01_real_bugs.md) | Medium | High-confidence fixes: double-gap padding, magic constants, hand-rolled scaffolds, same-level cascade inconsistencies, unused dep, one >80-char body line. |
| [`02_design_constants_additions.md`](02_design_constants_additions.md) | Medium | New tokens to add to `DesignConstants` (and mirror in FlutterCRM): pill heights, button heights, fixed control widths. |
| [`03_widget_hygiene.md`](03_widget_hygiene.md) | Low | Lower-priority widget-placement / shared-vs-feature consolidations. Not bugs — improve consistency over time. |
| [`04_claude_md_updates.md`](04_claude_md_updates.md) | Doc | Three small additions to `CLAUDE.md`: bless `_kFoo` for scroll math, carve out import line lengths, document `core/navigation/`. |

## Out of scope (per user direction)

These categories were checked but explicitly dropped:
- **Figma inventory** — figma is being removed from the project.
- **Mock data quality** ("John Doe" / repeated names / asset reuse) — user doesn't care for prototype.
- **`mockX` vs `kMockX` naming** — leave as-is.
- **Splitting `mock_stats.dart`** — splitting tight data classes hurts readability.
- **`benefits_list.dart` flat cascade** — verified against Figma `PhotoVerifactionStart` (264:346); the flat cascade matches the design (image bulk creates the visual separation).

## Recommended fix order

1. **Mechanical / low-risk first** — drop `cupertino_icons` from `pubspec.yaml`; rewrap the >80-char line in `class_list_item.dart:88`; replace magic `100` radius in `app_outline_button.dart:38`; replace `paddingBig * 2` in `profile_screen.dart:25`.
2. **CLAUDE.md doc updates** ([04](04_claude_md_updates.md)) — three small edits, no code impact.
3. **Add `DesignConstants` tokens** ([02](02_design_constants_additions.md)) — propose names, add to both MobileApp and FlutterCRM in the same change, then replace the 5 inline literals.
4. **Spacing fixes** — drop the double-padding in `class_reserve_footer.dart` and `video_recc_header.dart`; align the cascade in `class_screen._Body`, the two video carousels, and `rewards_body.dart`; tighten the title→description in `photo_verification_card.dart`.
5. **Scaffold migrations** — migrate `home_screen.dart` to `AppScreenScaffold`; refactor `PostClassScaffold` to compose `AppScreenScaffold` (the 5 post-class screens stay unchanged).
6. **File moves** — move `home_booked_body.dart` and `home_not_booked_body.dart` out of `screens/`.
7. **Widget hygiene** ([03](03_widget_hygiene.md)) — defer until a clean window; not blocking any feature.

## How the audit was produced

10 audit subagents ran in parallel (one per rule category). Each one searched the codebase, read cited files in context, and reported violations. Findings were then narrowed with the user, several subagent claims were downgraded after spot-checking (e.g. `selfie_circle.dart` is used in 3 places, not 7+; `video_recc_header.dart` is not a duplicate of `_SectionHeader`), and two flat-cascade calls were verified against Figma screenshots before being kept or dropped.
