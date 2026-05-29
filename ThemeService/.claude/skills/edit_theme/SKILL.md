---
name: edit_theme
description: >-
  Change the theme of an existing customization run, in place — four levers:
  (1) re-make specific slots, (2) edit the brand brief, (3) fill missing slots,
  (4) full in-place re-run (regenerate the whole run, incl. images).
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
  not-yet-done slots via scripts/expand/run.py; or "regenerate the whole run",
  "re-roll everything", "redo this run from scratch in place" → a full in-place
  re-run via the normal pipeline (src/cli.py) pointed at the existing run folder
  with --run-name, regenerating EVERY slot (incl. images) and overwriting the
  folder. regen preserves every slot you don't name and harmonises the ones you
  do; edit_customization re-validates the brief before writing; expand only
  generates what's absent. The per-slot levers (regen/expand) do NOT touch
  images — those have their own regen_image skill/script (create-new vs
  edit-current) — but the full in-place re-run does. To redo ONLY a slot's
  background removal without re-generating the image — "the cutout is bad",
  "re-strip the background", "redo the bg on the logo" → scripts/remove_bg/run.py
  (reads images/<slot>.raw.png, overwrites final_images/<slot>.png, no
  image-gen call). Trigger on anything "tweak / re-roll / restyle / re-brief /
  finish this run / regenerate everything / fix the cutout" shaped, even when
  not named.
---

# edit_theme — change a run's theme in place

Four levers on an existing run. The first three are surgical (never a full
re-generation); the fourth IS a full re-generation, in place.

1. **Re-make slots** — `scripts/regen/run.py`: re-roll one or more
   **colour / font / text / icon** slots. Everything you don't name
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
4. **Full in-place re-run** — a normal pipeline run (`src/cli.py`) pointed at
   the existing run folder via `--run-name`: regenerates **every slot, images
   included**, and overwrites the folder. This is "regenerate the whole run
   based on what it has". See Lever D.

Pin down *which run*, *which lever*, and the specifics; confirm spend for any
generation; run the script; report. **Re-make and fill spend money** (the LLM
calls for the slots produced, plus any provider cost their module incurs);
editing the brief is **free** (no model calls) but **only takes effect when you
then regenerate**; the **full in-place re-run spends the most** — it remakes
everything.

## IRON-CLAD RULE — change runs only through the scripts

Change an existing run **only** through the scripts: `regen` (slots),
`edit_customization` (brief), `expand` (fill missing), `regen_image` (images),
`remove_bg` (re-strip an image slot's background — Lever E), or a full pipeline
run (`src/cli.py`).

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
  (create-new vs edit-current-image). To fix *only* a bad cutout without
  re-generating the image, that's `remove_bg` (Lever E): it re-runs the
  background pass on the existing raw — no image-gen call, no `--spec`.

### Run generations sequentially — never in parallel (rate limits)
The pipeline hits rate-limited LLM / image providers. **Never fan out
generations concurrently.** When a request covers more than one run (e.g.
"regenerate every app", a batch of `regen` / `expand` / full re-runs), run them
**strictly one at a time** — each script invocation finishes before the next
starts (a sequential `for` loop, not background jobs launched in parallel, not a
single command with `&`, not multiple concurrent tool calls). It is fine to run
*one* long generation in the background to monitor it, but only ever one
in flight. This applies to **every** lever that spends (A `regen`, C `expand`,
D full re-run) and to any future batching — sequential is the hard default;
parallelism across runs is never an optimisation to reach for here.

## Lever A — re-make slots (`regen`)
1. Locate the run dir `apps/<app_id>/<run_id>/` (holds `app.yaml`,
   `customization.yaml`, `output.yaml`); ask if unnamed.
2. Identify the slot id(s) — colour/font/text/icon (the script lists
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

## Lever D — full in-place re-run (regenerate the whole run)
"Regenerate this run from what it has." Unlike A–C, this re-makes **every slot,
images included**, and **overwrites the whole folder**. It's just a normal
pipeline run (`src/cli.py`) whose `--run-name` is the existing run id, so it
lands back in the same directory:
```
poetry run python -m src \
    --app-yaml apps/<app_id>/<run_id>/app.yaml \
    --customization-yaml apps/<app_id>/<run_id>/customization.yaml \
    --run-name <run_id>
```
- **`--app-yaml` choice:** point at the run's **own snapshot**
  (`apps/<app_id>/<run_id>/app.yaml`) for a faithful re-roll of what the run
  has, or at the **live** `apps/<app_id>/app.yaml` to also pick up manifest
  (slot-inventory / description) changes.
- The pipeline detects the existing artifacts, **logs a `WARNING`, clears the
  produced artifacts** (`output.yaml`, `expansion_cost.yaml`, `images/`,
  `final_images/`, `icons/`) — keeping the `app.yaml` / `customization.yaml`
  inputs — and regenerates. **No interactive confirmation**: it warns and logs
  progress, then proceeds. A safety rail refuses if the run dir isn't under an
  `apps/` output root.
- It **spends the most** of any lever (everything is re-made). Tell the user
  that and which folder will be overwritten *before* you launch it; the warning
  is the gate, there is no prompt.

## Lever E — re-remove background (`remove_bg`)
Redo **only** the background pass for image slot(s) — when the image itself is
fine but its cutout is wrong (halo left behind, over-cropped, or the background
wasn't stripped). It reads the slot's existing raw and overwrites the
deliverable; it does **not** generate a new image (no image-gen call, no
`--spec`/`--mode`), and needs **no** `app.yaml`/`customization.yaml` — just the
run dir and the slot id(s):
```
poetry run python scripts/remove_bg/run.py \
    --run-dir apps/<app_id>/<run_id> \
    --slot <image_id> [--slot <image_id> ...]
```
- **Input** `images/<slot>.raw.png` (the solid-background raw) → **output**
  `final_images/<slot>.png`, **hard-overwritten with NO backup** — the prior
  cutout is not kept. This is the sanctioned, script-based way to touch
  `final_images/` (so it doesn't break the iron-clad rule), but warn the user
  the old cutout is gone.
- A wrong slot id fails before spending, listing the raws actually present.
- Each slot is **one paid Recraft `removeBackground` call (~$0.01)** — cheap,
  but it spends, so confirm and run slots **sequentially** (the script already
  does; never fan out). It writes **no** ledger entry (`expansion_cost.yaml` is
  untouched) — it's a deliberately standalone utility.
- If the remover fails 3× for a slot it falls back to the un-removed raw
  (the final still has a background) and the script flags it as `FALLBACK`
  and exits non-zero — re-run or escalate.

## Report
Say which slots regenerated + the pass cost, or which brief fields changed.
Offer to open affected outputs. A re-roll is just running again (LLM output
varies); a fundamentally-off look means steering (`--spec`) or a brief edit.

## Anti-patterns
- Never hand-edit `output.yaml`, the ledger, or files in `final_images/` /
  `images/` / `icons/`; never raw-edit `customization.yaml` — use
  `edit_customization`. Unsupported ⇒ tell the user (feature request).
- Never guess the run dir, the slots, or the brief field — ask when ambiguous.
- Never run a per-slot re-make (Lever A) without confirming the spend first.
  Lever D (full in-place re-run) is the deliberate exception: it has **no
  interactive gate** — the pipeline's `WARNING` is the gate — but you still tell
  the user which folder gets overwritten and that it spends, before launching.
- Per-slot levers never regenerate images — that's `regen_image`. Only Lever D
  (a full pipeline run) re-makes images, by design.
- `remove_bg` (Lever E) re-strips a cutout, it does **not** re-generate the
  image — don't reach for it to change *what* the image is (that's
  `regen_image`). It still spends (~$0.01/slot, Recraft) and hard-overwrites
  `final_images/<slot>.png` with no backup, so confirm before running and keep
  slots sequential.
- Never claim a brief edit took effect on its own — it needs a `regen`/full run.
- Never run generations in parallel — no concurrent runs, no `&`, no parallel
  background jobs, no batched fan-out. Sequential, one run in flight at a time,
  because the providers are rate-limited (see "Run generations sequentially").
- Never use bare `python3` / `.venv/bin/*` — `poetry run` only.
