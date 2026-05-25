---
name: edit_theme
description: >-
  Change the theme of an existing customization run, in place — three levers:
  (1) re-make specific slots, (2) edit the brand brief, (3) fill missing slots.
  Use this skill whenever the user wants to adjust an apps/<app_id>/<run_id>/
  run without a full re-generation: "regenerate the primary colour warmer",
  "re-roll the display font", "redo the booking headline", "make the accent and
  primary more muted", "regen <slot>" → re-make those slots via
  scripts/regen/run.py (a LIST of --slot ids + an optional --spec); or "change
  the brand name", "make the brief darker / more playful", "edit the colour
  direction", "set mode to dark" → edit the brief via
  scripts/edit_customization/run.py (flattened --name / --short-desc /
  --long-desc / --colors-description / --mode); or "finish this run", "it's
  missing the icons", "I added a slot, generate just it", "resume" → fill the
  not-yet-done slots via scripts/expand/run.py. regen preserves every slot you
  don't name and harmonises the ones you do; edit_customization re-validates
  the brief before writing; expand only generates what's absent. IMAGES are NOT
  handled here — they have their own regen_image skill/script (create-new vs
  edit-current). Trigger on anything "tweak / re-roll / restyle / re-brief /
  finish this run" shaped, even when not named.
---

# edit_theme — change a run's theme in place

Three levers on an existing run, never a full re-generation:

1. **Re-make slots** — `scripts/regen/run.py`: re-roll one or more
   **colour / font / text / icon / lottie** slots. Everything you don't name
   is preserved **verbatim**; the kept slots are shown to the model as fixed
   context so the re-made ones harmonise (colour re-checks WCAG-AA against the
   fixed background/text).
2. **Edit the brief** — `scripts/edit_customization/run.py`: a validated,
   targeted edit of a run's (or app's) `customization.yaml` — the brand brief
   that drives generation.
3. **Fill missing slots** — `scripts/expand/run.py`: generate only the slots
   declared in `app.yaml` but absent from `output.yaml` (resume a partial run,
   or add a slot to the dir's `app.yaml` and fill just it). Everything already
   present is preserved.

Pin down *which run*, *which lever*, and the specifics; confirm spend for any
generation; run the script; report. **Re-make and fill spend money** (the LLM
calls for the slots produced, plus any provider cost their module incurs);
editing the brief is **free** (no model calls) but **only takes effect when you
then regenerate**.

## IRON-CLAD RULE — change runs only through the scripts

Change an existing run **only** through the scripts: `regen` (slots),
`edit_customization` (brief), `expand` (fill missing), `regen_image` (images),
or a full pipeline run (`src/cli.py`).

**Never hand-edit a produced artifact** — do not open `output.yaml` and change
a value, do not rename/overwrite a file in `final_images/` / `images/` /
`icons/`, do not patch the ledger. Even the brief is edited through
`edit_customization` (it re-validates), not raw text munging.

If the user wants something these scripts **cannot** express, do **not** work
around it by editing artifacts. Stop and **tell the user** plainly what's not
supported, so they can add it as a feature. A missing capability is a feature
request, never a manual edit.

## Operating principles

### No assumptions
Package rule (`CLAUDE.md`), verbatim: *"When a decision has more than one
reasonable answer, ask and wait for the user's explicit response. Never assume,
recommend-and-proceed, or defer the choice unilaterally."* If the run dir, the
slots, or which brief field is meant is ambiguous, ask (`AskUserQuestion`).

### Know the scope
- `regen` re-makes only the slots you pass and keeps the rest. Slots of the
  **same atomic node** (e.g. two colours) re-roll **together** in one
  harmonised call.
- A brief change (`edit_customization`) does **nothing on its own** — it edits
  the file. To see it, `regen` the affected slots (or do a full run). And
  regenerating an upstream node does **not** refresh already-done dependents.
- **Images are out of scope here** — route image re-rolls to `regen_image`
  (create-new vs edit-current-image).

## Lever A — re-make slots (`regen`)
1. Locate the run dir `apps/<app_id>/<run_id>/` (holds `app.yaml`,
   `customization.yaml`, `output.yaml`); ask if unnamed.
2. Identify the slot id(s) — colour/font/text/icon/lottie (the script lists
   valid ones on a wrong id; or read `app.yaml`). Confirm any described-in-words
   slot.
3. Confirm spend, then from the package root (`poetry run` mandate in
   `CLAUDE.md`):
   ```
   poetry run python scripts/regen/run.py \
       --run-dir apps/<app_id>/<run_id> \
       --slot <slot_id> [--slot <slot_id> ...] [--spec "make it warmer"]
   ```
   `--spec` is one optional instruction applied to every named slot (say
   everything in words, including anything to avoid); omit to just re-roll. It
   preserves the original `cost` and appends a `regenerate` entry to
   `expansion_cost.yaml`.

## Lever B — edit the brief (`edit_customization`)
Edit the run's (or app's) `customization.yaml`. Five flattened, optional flags;
only the ones you pass change, the file is re-validated before writing:
```
poetry run python scripts/edit_customization/run.py \
    --file apps/<app_id>/<run_id>/customization.yaml \
    [--name "…"] [--short-desc "…"] [--long-desc "…"] \
    [--colors-description "…"] [--mode light|dark]
```
For a substantial brand/voice rewrite, prefer the **`brand-brief`** skill (it
authors the whole brief interactively); use `edit_customization` for targeted
field edits. After editing a run's brief, **`regen` the affected slots** so it
takes effect (a `colors_direction` change is a colour re-roll; a
`design_direction` change affects prompt-driven slots).

## Lever C — fill missing slots (`expand`)
Generate only the slots that are **declared in `app.yaml` but absent from
`output.yaml`** — a resume of a partial run, or filling a slot just added.
Everything already present is preserved; it never re-makes a slot that's
already there (that's `regen`).
```
poetry run python scripts/expand/run.py --run-dir apps/<app_id>/<run_id> \
    [--app-yaml apps/<app_id>/app.yaml]
```
The run dir's `app.yaml` is a frozen **snapshot** — so to fill a slot the user
just added to the **live** `app.yaml`, pass it with `--app-yaml` (the dir's
snapshot is then refreshed to match). Without `--app-yaml` the snapshot is used
as-is (the resume case). It prints what it will fill, exits cleanly with no
spend if nothing is missing, and appends an `expand` entry to
`expansion_cost.yaml`.

## Report
Say which slots regenerated + the pass cost, or which brief fields changed.
Offer to open affected outputs. A re-roll is just running again (LLM output
varies); a fundamentally-off look means steering (`--spec`) or a brief edit.

## Anti-patterns
- Never hand-edit `output.yaml`, the ledger, or files in `final_images/` /
  `images/` / `icons/`; never raw-edit `customization.yaml` — use
  `edit_customization`. Unsupported ⇒ tell the user (feature request).
- Never guess the run dir, the slots, or the brief field — ask when ambiguous.
- Never run a re-make without confirming the spend first.
- Never regenerate an image here — that's `regen_image`.
- Never claim a brief edit took effect on its own — it needs a `regen`/full run.
- Never use bare `python3` / `.venv/bin/*` — `poetry run` only.
