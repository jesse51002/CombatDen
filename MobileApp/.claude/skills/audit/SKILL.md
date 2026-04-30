---
name: audit
description: Audit the MobileApp codebase against the rules in CLAUDE.md. Use when the user asks to "audit", "review the rules", "check coding standards", "find violations", or "see if X is compliant". Produces a tiered findings report (real bugs vs doctrine questions vs dismissed) and surfaces patterns that suggest CLAUDE.md itself needs updating.
---

# Audit skill

The job is to find **real problems** in the codebase against `MobileApp/CLAUDE.md`. Not to inflate the violation count. Not to nitpick. Not to flag every literal that grep can find.

CLAUDE.md is strict by design. Most rules are non-negotiable — colors, fonts, icons, scaffold, spacing, dead code. Treat them that way. **But:** some rules have legitimate exceptions baked in, some require context to evaluate, and some get overtaken by reality (CLAUDE.md drifts). When that happens, surface it — don't pretend the rule is broken when the rule is the one that's wrong.

## Default stance: strict

A finding is a finding. The codebase is held to the rules as written:
- Inline `Color(0x...)` outside `design_constants.dart` / `app_theme.dart` → violation.
- Inline `fontSize:` / `fontWeight:` / `fontFamily:` → violation.
- `Icons.*` instead of `Symbols.*_sharp` → violation.
- `Icon(...)` missing `weight:` or `size:` token → violation.
- Hand-rolled `Scaffold` instead of `AppScreenScaffold` → violation.
- `SizedBox(height: N)` between siblings inside a `Column` → violation.
- `Padding(top: ...)` to fake a gap between siblings → violation.
- Relative imports (`../foo.dart`) → violation.
- Commented-out code → violation.
- New runtime dependencies beyond `google_fonts` and `material_symbols_icons` → violation.

Don't soften these. Don't hand-wave them. If they're in the code, list them.

## Allowed exceptions (don't flag these)

These are **explicitly blessed** in CLAUDE.md. Read it before auditing — don't audit from memory.

- **Image dimensions** — `Image.asset(width:, height:)`, asset-bound `SizedBox(width:, height:)` constraints, `aspectRatio:` for images, and `Positioned(left:/top:/...)` math when laying out an image overlay are **fine**. Don't flag them.
- **`_kFoo` private constants** — for image dimensions, scroll-position math, sliver heights, pinned-header heights, or pure layout arithmetic that has no `DesignConstants` equivalent. Examples: `_kTopbarHeight = 268`, `_kCardWidth = 258`. **Fine.**
- **`StatefulWidget` with controllers** — `ScrollController`, `PageController`, `TabController`, `AnimationController`, or `GlobalKey` for layout measurement. **Fine.** Only flag stateful widgets that hold business/data state.
- **`SafeArea` inside `AppScreenScaffold`** — only fine when the scaffold's defaults don't fit (e.g. a screen whose topbar is inside the scrollable so it skips top safe-area). Flag if it's just redundant nesting.
- **`debugPrint('TODO: ...')`** as a button callback — this is the prototype convention for "no-op for now". **Fine.**
- **`.copyWith(color:)` on a `DesignConstants.*` text style** — extending a token style with a color override is the documented escape hatch. **Fine.** Only flag raw `TextStyle(...)` constructors with hardcoded values.
- **`width:` / `height:` on a `SizedBox` that wraps an `Image.asset`** — image-bound, see above. **Fine.**

## The three-bucket model

Every finding goes in one of three buckets. **Most subagent reports get this wrong** by mashing real bugs together with doctrine questions; don't.

### Bucket 1: real bugs

Concrete, isolated violations. Easy to fix. The rule is right and the code is wrong.

Examples from past audits:
- `app_outline_button.dart:38` — `borderRadius ?? 100` (magic radius literal).
- `class_reserve_footer.dart:14-15` — `Padding(top: spacingBig)` faking a sibling gap when the parent should own the spacing.
- `home_screen.dart:31` — hand-rolled `Scaffold` instead of `AppScreenScaffold`.
- One body line at 82 chars when the limit is 80.
- Unused dependency in `pubspec.yaml`.
- Hardcoded `width: 120` on a styled `Container` (not image-bound).

These get fixed. No discussion needed.

### Bucket 2: doctrine questions (escalate to user)

The same "violation" appears in N places, all defensible, with no clean fix that preserves the intent. **This is a signal CLAUDE.md needs updating, not a signal you have N bugs.**

The threshold is roughly: **3+ instances of the same shape, all defensible.** When you see this, don't list 3 violations — list it once and propose a CLAUDE.md amendment.

Examples from past audits:
- 102 over-80-char lines, every one a deep `package:mobile_app/...` import that `dart format` won't break. → Don't fix 102 imports. Carve out import lines from the 80-char rule.
- 8 sites using `_kFoo` for scroll-position math. CLAUDE.md only blesses `_k` for image dimensions. → Bless `_k` for layout math too.
- `lib/core/navigation/app_routes.dart` exists but isn't in the documented project structure. → Update the doc; don't move the file.
- 5 inline `width`/`height` literals on pills/tabs/buttons (24, 30, 50, 70, 120). `design_constants.dart` is IMMUTABLE and has no control-height tokens. → Either add tokens (and mirror to FlutterCRM) or refactor to intrinsic sizing. Either way, this is a doctrine call, not 5 bugs.

When escalating, propose the specific edit to CLAUDE.md (or to `design_constants.dart`). Don't just say "this is a doctrine question" — say what the new rule should be.

### Bucket 3: subjective / verify against Figma

Some "violations" are design judgments that may match the Figma frame. Flag them with low confidence and check Figma before declaring a fix.

Examples:
- A "flat cascade" (all `spacingLarge` at every nesting level). Could be a hierarchy bug, or could be intentional because image bulk creates the visual separation. **Verify** by fetching the Figma screenshot (`mcp__plugin_figma_figma__get_screenshot` with the `node_id` from `figma/inventory.yaml`).
- A horizontally-padded section that breaks the screen-edge inset rule. Maybe the design wants extra inset.
- Two adjacent components with mildly different gaps. Maybe it's a bug, maybe it's a design decision.

If the Figma matches the code, dismiss the finding. If it doesn't, move it to Bucket 1.

## Verify everything before writing it down

Subagents lie. So does grep. So does memory. Don't trust them.

**Before any line:number reference goes into the report:**

1. **Read the file at the cited line** with the `Read` tool. Confirm the quoted snippet matches what's actually there.
2. **Check the file still exists.** Refactors happen mid-session; a path the subagent cited an hour ago may have been deleted. Past audits had subagents cite `summary_cta.dart` and `session_summary_row.dart` — neither existed.
3. **Cross-reference grep hits with context.** A `Color(0xFF...)` inside `design_constants.dart` is the source of the token, not a violation. A `width: 75` inside `Image.asset(...)` is fine; the same `width: 75` on a styled `Container` is not.
4. **Check the caller count when proposing a refactor.** "Move to shared/" is a different recommendation if a widget is used 1 time vs 7 times. Past audit overstated `selfie_circle.dart` as "used in 7+ places" — it's 3.
5. **Diff `design_constants.dart` against FlutterCRM** before writing the audit. The two files must be byte-identical. `diff` returns nothing if compliant.

## How to run the audit

The shape that worked well in past sessions:

1. **Read CLAUDE.md.** All of it. Don't skim. Specifically re-read the "Theming System", "Spacing rules", "Section Structure & Gap Hierarchy", and "Always delete dead code" sections — those are where most violations cluster.
2. **Run `flutter analyze`.** If it's not clean, that's the first finding.
3. **Spawn parallel subagents for independent rule categories.** Categories that work well in parallel: theming (colors/fonts/spacing/radius/borders), icons, sibling-spacing/cascade, scaffold usage, dead code, file organization, mock data discipline, widget placement (shared vs feature), imports/naming. Don't spawn one giant agent — context bloat hurts quality.
4. **For each subagent finding, verify against the actual file.** Spot-check 2-3 random citations per category before trusting the rest.
5. **Re-bucket every finding.** Subagents tend to dump everything as "violation". You re-classify into the three buckets above.
6. **Surface doctrine questions.** Don't just write them down — propose the CLAUDE.md edit and ask the user.
7. **Write the audit to `MobileApp/audit/`.** One file per category at most. README on top with the headline table and recommended fix order.

## Output structure

```
audit/
├── README.md                     # index, headline table, fix order, what was dropped
├── 01_real_bugs.md               # Bucket 1
├── 02_doctrine_questions.md      # Bucket 2 — proposed CLAUDE.md / DesignConstants edits
└── 03_verify_against_figma.md    # Bucket 3 — items that need a design check before "fixing"
```

Each finding entry uses this format:

```markdown
### `lib/path/to/file.dart:LINE`

```dart
<short verbatim quote>
```

- **Rule** ("CLAUDE.md section name"): "<exact quoted rule>"
- **Context**: <why it's a real bug / where else it's used / what the caller looks like>
- **Fix**: <concrete change>
```

The `**Rule**` line is non-negotiable — every finding must cite the exact CLAUDE.md section it breaks. This makes it easy for the user to verify the audit is right, and it makes it obvious when a "violation" is really a CLAUDE.md gap (no rule cited cleanly = doctrine question, not bug).

## Anti-patterns to avoid

- **Flagging without reading.** A grep hit is not a finding. Read the file.
- **Inflating the count.** 102 import-length "violations" looks impressive and means nothing — it's one doctrine question.
- **Citing non-existent files.** Verify the path before writing it.
- **Vague "should be improved" findings.** Either cite a rule or drop the finding.
- **Burying real bugs under stylistic preferences.** Bucket 1 stays small and concrete.
- **Treating CLAUDE.md as immutable.** When the codebase consistently does X and CLAUDE.md says don't-X, the doc is the thing that's wrong. Propose the amendment.
- **Skipping the Figma check.** "This cascade looks flat" is not a finding until you've compared to the Figma frame.
- **Writing the audit before talking to the user.** When you find 5+ doctrine questions, surface them mid-audit and let the user steer scope. Don't write 5 audit files only to have 4 of them be "drop this category".

## When the user pushes back

If the user says "drop X" or "this category doesn't matter" — drop it cleanly. Move it to a "What's explicitly NOT in scope" section in the README so future-you knows why it was excluded. Don't argue.

If the user says "are you sure all of these are real?" — that's the cue to re-bucket. Walk back any finding you can't defend with a specific rule citation. Honesty beats coverage.
