---
name: quality-audit
description: Audit the codebase against the rules in CLAUDE.md. Use when the user asks to "audit", "review the rules", "check coding standards", "find violations", or "see if X is compliant". Produces a tiered findings report and surfaces patterns where CLAUDE.md itself may need updating.
---

# Quality audit skill

The job is to find **real problems** against `CLAUDE.md`. Not to inflate the violation count. Not to nitpick. Not to flag every literal that grep can find.

## Source of truth: CLAUDE.md

Always read CLAUDE.md (and any nested CLAUDE.md files in the directory you're auditing) at the start of every audit. Do not audit from memory of past sessions — rules change, exceptions get added, the doc evolves. The rules in the doc at the time you read it are the rules you enforce.

This skill does not list specific rules. That would drift. Read the doc.

## Default stance: strict

If CLAUDE.md says "NEVER X" or "ALWAYS Y", treat that as non-negotiable. Don't soften, don't hand-wave. If the code does X, list it.

The exception is the doctrine-question case below — when fixing the violation would *hurt* the codebase, surface it to the user instead of fixing it.

## The thinking pattern: three buckets

Every finding goes in one of three buckets. Subagents tend to dump everything as "violation" — re-classify before writing.

### Bucket 1 — real bugs

Concrete, isolated. The rule is right and the code is wrong. Fixing makes the code better. **Fix.**

### Bucket 2 — doctrine questions (escalate to user)

The same "violation" appears in N defensible places, with no clean fix that preserves the intent. **This is a signal CLAUDE.md needs updating, not a signal you have N bugs.**

Trigger: roughly **3+ instances of the same shape**, all defensible, where any "fix" would either (a) be a no-op churn, (b) require a refactor that hurts readability or simplicity, or (c) require infrastructure that doesn't exist (a token, a tool flag, a folder rename).

When this fires:
- **Don't list N violations.** List the pattern once.
- **Propose the specific edit** to CLAUDE.md or to the supporting infrastructure (e.g. "add this token to `design_constants.dart`", "add this carve-out to the rule").
- **Ask the user.** Don't make the doc edit unilaterally. The user owns the rules.

The acid test: *if I fixed all N instances right now, would the codebase be better, the same, or worse?* If "the same" or "worse", it's a doctrine question, not a bug.

### Bucket 3 — verify against design (or other context)

Some violations are judgment calls that depend on context the code doesn't carry — the active design source, a product decision the user has stated elsewhere. Examples: gap hierarchy that may match the design, layout choices that look "wrong" but are intentional.

Flag with low confidence and **verify before declaring a fix.** If the design matches the code, dismiss. If it doesn't, move to Bucket 1.

If the source of truth is unavailable, ask the user to make the call rather than guessing.

## Verification discipline (don't trust grep, don't trust subagents)

Before any `path:line` reference goes into the report:

1. **Read the file at the cited line.** Confirm the quoted snippet matches what's actually there.
2. **Check the file still exists.** Files get refactored mid-session — paths can rot in minutes.
3. **Cross-reference grep hits with context.** A token reference inside the token-definition file is the source, not a violation. An inline literal inside a widget is a violation. Same regex, opposite verdicts.
4. **Check caller counts when proposing a refactor.** "Move to shared/" reads differently for a 1-caller widget vs a 7-caller widget.
5. **For any "X is missing/duplicated/wrong" claim, verify with `grep`/`find`/`Read`.** Don't pass through subagent claims unverified.

## Output structure

Write the audit to a **date-stamped subfolder** under `audit/`:

```
audit/
├── YYYY-MM-DD/
│   ├── README.md              # index, headline table, fix order, what was dropped
│   ├── 01_real_bugs.md        # Bucket 1
│   ├── 02_doctrine_questions.md  # Bucket 2 — proposed CLAUDE.md / infra edits
│   └── 03_verify_first.md     # Bucket 3 — items that need a design / product check
└── YYYY-MM-DD/                # next audit run
    └── ...
```

Use today's date. Don't overwrite previous audits — they're history.

Each finding entry uses this format:

```markdown
### `path/to/file.ext:LINE`

```
<short verbatim quote>
```

- **Rule** ("CLAUDE.md section name"): "<exact quoted rule>"
- **Context**: <why it's a real bug / where else it's used / what the caller looks like>
- **Fix**: <concrete change>
```

The `**Rule**` line is non-negotiable. If you can't cite the exact CLAUDE.md section a finding breaks, the finding is not Bucket 1 — it's Bucket 2 (the rule doesn't exist or doesn't fit) or it gets dropped.

## How to run an audit

1. **Read CLAUDE.md** (and any nested CLAUDE.md files). All of it.
2. **Run whatever static analysis the project has** (`flutter analyze`, `tsc`, `cargo clippy`, etc.). If it's not clean, that's the first finding.
3. **Spawn parallel subagents for independent rule categories.** Don't spawn one giant agent — context bloat hurts quality. Categories that work well in parallel: theming/styling, naming/imports, file organization, dead code, scaffold/structure, dependencies, mock/test discipline.
4. **Verify each subagent finding** against the actual file. Spot-check 2-3 random citations per category before trusting the rest.
5. **Re-bucket every finding** into the three buckets above.
6. **Surface doctrine questions to the user mid-audit.** Don't write the audit then ask. Ask, then write.
7. **Write to `audit/YYYY-MM-DD/`.** README on top with the headline table and recommended fix order.

## Anti-patterns to avoid

- **Flagging without reading.** A grep hit is not a finding.
- **Inflating the count.** 100 instances of the same defensible pattern is one doctrine question, not 100 bugs.
- **Citing non-existent files.** Verify the path before writing it.
- **Vague "should be improved" findings.** Either cite a rule or drop the finding.
- **Treating CLAUDE.md as immutable.** When the codebase consistently does X and CLAUDE.md says don't-X, the doc is the thing that's wrong. Propose the amendment.
- **Skipping the design check.** "This looks wrong" is not a finding until you've checked the source of truth.
- **Writing the audit before talking to the user.** When you find doctrine questions, surface them mid-audit and let the user steer scope.
- **Auditing from memory.** Rules in CLAUDE.md change. Read it every time.

## When the user pushes back

- "Drop X" / "this category doesn't matter" → drop cleanly. Note it in the README's "What's NOT in scope" section so future-you knows why.
- "Are you sure all of these are real?" → re-bucket. Walk back any finding you can't defend with a specific rule citation. Honesty beats coverage.
- "Update CLAUDE.md to allow X" → that's a separate edit. Do it explicitly. Don't slip doc changes into an audit run.
