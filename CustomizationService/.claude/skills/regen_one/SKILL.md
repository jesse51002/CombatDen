---
name: regen_one
description: >-
  Regenerate ONE image slot of an existing customization run, in place, under
  the current image-prompt rule. Use this skill whenever the user wants to
  re-roll, regenerate, redo, or refresh a single generated image — says
  "regenerate the celebration image", "re-roll the trophy", "the logo came out
  wrong, redo it", "regen <slot>", "make a new version of this one image", or
  points at one slot in an apps/<app_id>/<run_id>/ run and wants it remade
  without re-running the whole pipeline. It drives a single ImageNode via
  scripts/regen_one/run.py: re-writes that slot's prompt, re-classifies
  complexity, regenerates the image, runs background removal/crop, overwrites
  the slot's files in place, and surgically updates only that slot's prompt +
  complexity in output.yaml. If the user ALSO wants to change the brand brief
  (customization.yaml) — a new look, tone, mascot, colour mood — make that
  edit too (via the brand-brief skill for real authoring, or a small targeted
  edit), validate it, then regenerate so the change takes effect. Reuses the
  run's saved palette and never re-runs colours/fonts/text — for a colour
  change a full pipeline run is still required. Trigger on anything
  single-image re-roll / "redo just this asset" shaped, even when not named.
---

# regen_one — regenerate a single image slot in place

You re-roll **one** image of an existing run and write the result back over the
old files. The atomic unit is one image (the pipeline's own contract), so this
never re-runs colours, fonts, or text — it reuses the palette already saved in
that run's `output.yaml`.

The work is done by `scripts/regen_one/run.py`. Your job is to pin down *which
run* and *which slot*, optionally apply a requested `customization.yaml` change
first, run the script, and report what changed. **This call spends money** (an
Opus prompt-write + a Gemini complexity classify + a gpt-image-2 generation + a
PhotoRoom cutout), so confirm before running.

## Operating principles

### No assumptions

Package rule (`CLAUDE.md`), verbatim: *"When a decision has more than one
reasonable answer, ask and wait for the user's explicit response. Never assume,
recommend-and-proceed, or defer the choice unilaterally."* If the run dir or
the slot is ambiguous, ask (`AskUserQuestion`) — never guess which image they
meant.

### Know the scope, and say it when it matters

- Regen reuses the **saved palette** from `output.yaml`. It does **not** re-run
  the colour node. So editing `colors_direction.description` in
  `customization.yaml` has **no effect** here, and changing
  `colors_direction.mode` only flips the prompt's light/dark background hint
  while the palette colours stay as they were — an inconsistency. If the user
  wants a real colour change, tell them plainly that needs a **full pipeline
  run** (the CLI in `src/cli.py`), not this skill.
- The prompt side **does** pick up edits: `design_direction` (name / short /
  long) and the slot's own description in `app.yaml` drive the prompt. So a
  brand-brief edit to `design_direction.long_desc` will change the regenerated
  image. (`app.yaml` is architect-owned — never edit it here.)

## Step 1 — Locate the run and the slot

1. The run dir is `apps/<app_id>/<run_id>/` and must hold `app.yaml`,
   `customization.yaml`, and `output.yaml`. If the user named one, use it; else
   `ls apps/` and the per-app run dirs and ask which (`AskUserQuestion`).
2. Identify the slot id. The script lists valid slot ids if you pass a wrong
   one; you can also read them from `app.yaml` (`images[].id`) or the
   `output.yaml` `image_set.images` keys. If the user described the image in
   words ("the booking celebration one"), map it to the slot id and confirm.

## Step 2 — (Optional) modify customization.yaml first

Only when the user asks to change the brand brief as part of this re-roll:

- **A real brand/voice/look rewrite** → use the **`brand-brief`** skill to
  author the change properly (it is the owner of `customization.yaml`,
  validates against the `Customization` model, and gets colour approval). Let
  it finish and write the file, then come back here.
- **A small, surgical tweak** the user states explicitly (e.g. one sentence
  added to `long_desc`) → edit `apps/<app_id>/customization.yaml` directly,
  then round-trip validate before regenerating:
  ```
  poetry run python -c "import sys,yaml; from schema.customization import Customization; Customization.model_validate(yaml.safe_load(open(sys.argv[1])))" apps/<app_id>/customization.yaml
  ```
  On a validation error, surface it verbatim and fix the field — never write a
  brief that fails to validate.

Reuse, do not duplicate: only the five writable fields exist
(`design_direction.{name,short_desc,long_desc}`, `colors_direction.{description,
mode}`); the brief is intent/prose, **never** colour values.

## Step 3 — Confirm spend, then run

State the cost (one image generation pipeline) and confirm. Then, from the
package root (so `.env` resolves), per the `poetry run` mandate in `CLAUDE.md`:

```
poetry run python scripts/regen_one/run.py \
    --run-dir apps/<app_id>/<run_id> --slot <slot_id>
```

The script overwrites the slot's files in `images/` and `final_images/` and
updates only that slot's `prompt` + `complexity` in `output.yaml` (every other
line stays byte-stable). It prints the old prompt next to the new one.

## Step 4 — Report

Show the user the old → new prompt diff the script printed, and offer to open
the regenerated `final_images/<slot_id>.png` so they can eyeball it. If they
don't like it, a re-roll is just running the script again (image models are
non-deterministic; a second pass often differs). If the look is fundamentally
off, the lever is the brief (`design_direction.long_desc`) or the slot
description — loop back to Step 2.

## Anti-patterns

- Never guess the run dir or the slot — ask when ambiguous.
- Never run the script without confirming the spend first.
- Never edit `app.yaml` or pipeline code; the only writable brief surface is
  `apps/<app_id>/customization.yaml`, and only when the user asked for a brief
  change.
- Never claim a colour change took effect — regen reuses the saved palette;
  colour changes need a full pipeline run.
- Never write a `customization.yaml` that fails the round-trip validation.
- Never use bare `python3` / `.venv/bin/*` — `poetry run` only.
- Never re-run the whole pipeline when the user asked for one image; this skill
  is the single-slot path.
