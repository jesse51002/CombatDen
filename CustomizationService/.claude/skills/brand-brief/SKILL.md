---
name: brand-brief
description: >-
  Interactively author a schema-valid customization.yaml brand brief for the
  AI customization pipeline. Use this skill whenever the user wants to onboard
  a new brand/app to the pipeline, write or rewrite a customization.yaml, says
  "set up a new app", "create a brand brief", "I have a new gym/business to
  customize", "draft the design direction", "fill in colors_direction", asks
  what to put in customization.yaml, or wants to revise an existing brief in
  apps/<app_id>/. This is a question-driven interview: it asks many structured
  and open questions, recommends researched options for every one but never
  picks for the user, reads the chosen app's app.yaml to ground its questions
  in that app's real slots, keeps colour direction GENERAL (mood / hue family /
  saturation + light or dark mode — never hex or oklch), then assembles,
  Pydantic-validates, and writes the YAML to an apps/<app_id>/ directory the
  user chooses. Trigger on anything brand-onboarding / customization.yaml /
  design-direction / colour-brief shaped, even when not named explicitly.
  Authors ONLY customization.yaml; it reads but never writes app.yaml or
  pipeline code.
---

# Brand Brief — authoring customization.yaml

You produce exactly **one** artifact: a `customization.yaml` that round-trips
against the `Customization` Pydantic model (`schema/customization.py`). It is
the only writable surface in the whole pipeline besides `app.yaml` (which is
architect-owned and off-limits here). Your entire value is asking sharper
questions than a blank file would — and refusing to answer them for the user.

The pipeline turns this brief plus an app's slot inventory into a fully
customized app (colours + images). The brief is *intent*, never *values*: it
says what the brand feels like and which way the colour should lean; the
pipeline's colour node decides the exact OKLCH numbers under hard rules the
brief must not fight.

## The writable surface (the whole of it)

From `schema/customization.py` — all models are `extra="forbid"`, so **any
other key fails validation**. There is no colour-value field, no slot list, no
nested structure beyond this:

- `design_direction.name` — short brand name shown in the app (non-empty)
- `design_direction.short_desc` — one-line essence (non-empty)
- `design_direction.long_desc` — the deep brand + visual-system prose
  (non-empty); this is where almost all the work goes
- `colors_direction.description` — GENERAL colour direction prose (non-empty)
- `colors_direction.mode` — exactly `light` or `dark` (`ColorMode`,
  `schema/color_mode.py`)

Five fields. Never invent a sixth.

## Operating principles (load-bearing)

### 1. No assumptions

The package rule (`CLAUDE.md`), verbatim: *"When a decision has more than one
reasonable answer, ask and wait for the user's explicit response. Never assume,
recommend-and-proceed, or defer the choice unilaterally. Presenting researched
options is encouraged; making the choice for the user is not."*

Every question offers 2–4 researched options, archetypes, or example phrasings,
then the user picks or free-writes. You never fill a field from inference,
never say "I'll go with X unless you object," and never silently expand a
one-word answer into prose without showing the prose back for approval.

### 2. Deep on brand, general on colour

Brand identity and design direction get extracted exhaustively — many
follow-ups, layered prose. Colour stays at mood / hue-family /
saturation-intent / mode level only. Tell the user *why*, so the limit is not
arbitrary: the pipeline owns precise values and enforces rules a hardcoded
colour would fight. Cite `src/modules/colors/prompts/color_palette_rule.md`
and the contract in `src/modules/colors/color_validation.py`:

- background & text must be low-chroma (≈0.003–0.04) with a faint brand tint,
  never pure grey/black;
- text must clear **WCAG AA ≥ 4.5:1** against the background;
- the **background lightness band**: near an extreme but held off it on both
  sides (dark L 8–30%, light L 86–90%) so the MobileApp client's translucent
  elevation veil has tonal room for cards/sheets to read (README TODO #1).

A hex/oklch in the brief is ignored at best and fights these rules at worst.

### 3. Question-driven, mixed modality

Use the `AskUserQuestion` tool where the answer space is enumerable (company
archetype, energy level, light/dark mode, design-feel axes). Use open
plain-text prompts where free expression is the point (the real story of the
business, the founder's own words for the voice, the hard nos). Never force
prose into a multiple-choice; never offer a multiple-choice for something that
needs the user's own sentences.

### 4. Ground every question in the real app

Before interviewing, locate and read the target app's `app.yaml`. The brief
feeds *every* slot's prompt, so tailor questions to the slots that actually
exist. Name real slots back to the user. Never invent a slot; never write
`app.yaml`.

## Step 0 — Locate the app and read its app.yaml

1. Ask which app this brief is for. `AskUserQuestion` listing the discovered
   `apps/<app_id>/` dirs (run `ls apps/`) plus a "new app" option.
2. **Existing app:** read `apps/<app_id>/app.yaml`. If a `customization.yaml`
   already exists there, read it and ask the user explicitly whether they are
   *editing* it or *replacing* it from scratch.
3. **New app:** explain that this skill authors only `customization.yaml`; the
   matching `app.yaml` slot inventory is architect-owned and must already
   exist. If there is no `app.yaml` for the new id, you cannot ground the
   questions — surface this and ask how to proceed (point at an existing
   `app.yaml` as a slot reference, or stop). Do not fabricate slots.
4. Read `apps/combatden/customization.yaml`,
   `apps/smoketest/customization.yaml`, and
   `tests/data/apps/demo/customization.yaml` for **voice and structure
   calibration only** — the house register (a bulleted visual-system block, a
   "Hard nos:" line, the Primary/Background/Text/Accent colour bullets). Never
   copy their content; the brand is the user's.
5. Summarize back: app id, slot count, the kinds of moments the slots cover
   (celebratory heroes vs persistent tiny utility icons vs the brand anchor),
   and the colour slots with their roles. This framing primes every later
   question.

See `references/archetypes.md` for the full option banks the steps below draw
from.

## Step 1 — The brand interview (deep)

Work through these in order. Each lists its modality and what field it feeds.

- **Q1 — Brand name** *(open, short → `name`)*. The name the user sees on the
  app bar. Recommend conventions (short, recognizable), never propose names.
- **Q2 — Company archetype** *(`AskUserQuestion` → frames `short_desc` /
  `long_desc`)*. Offer the researched archetypes from
  `references/archetypes.md`, each with a one-line descriptor, plus "something
  else / a blend" falling through to open prose. Say plainly this is a starting
  frame, not a box.
- **Q3 — One-line essence** *(open → `short_desc`)*. Show the house pattern
  shape from the real briefs (not their content). Offer 2–3 example phrasings
  derived from the Q2 answer as scaffolding the user can take, edit, or reject.
- **Q4 — The real story** *(open, layered → `long_desc` ¶1)*. Who is this for,
  what do they want, and what is the *opposite* of this brand (contrast sharpens
  identity). Follow up at least once to deepen a vague answer.
- **Q5 — Voice** *(structured axis assist + open → `long_desc`)*. A quick
  `AskUserQuestion` for the voice axis (warm-encouraging / calm-unhurried /
  bold-confident / playful-bubbly / understated-premium), then an open prompt
  for the user's *own words* and a concrete "what it must never sound like."
  The negative is as load-bearing as the positive.
- **Q6 — Mascot / hero element** *(`AskUserQuestion`, grounded in app.yaml)*.
  Does the app have a mascot-style hero or only an abstract mark / icon system?
  If a mascot: open prose for what it is and which real celebratory slots it
  stars in (name them from app.yaml).
- **Q7 — Visual system** *(open, multi-part — the deepest question →
  `long_desc`)*. Offer the five-line house scaffold and walk each as its own
  sub-prompt: *feel* (adjective cluster), *medium & materials*, *finish &
  light*, *energy by role* (name the app's real persistent vs celebratory
  slots and ask how energy should differ between them), *hard nos* (explicit
  prohibitions every brief carries). For each sub-prompt offer 2–3 example
  directions from the archetype as a menu the user edits or discards.

## Step 2 — The colour interview (deliberately shallow)

Open by stating to the user, in plain language: **we are not picking colours
here**, and why (principle 2, said for the user, not just internally).

- **C1 — Mode** *(`AskUserQuestion`, exactly `light` / `dark` + "explain the
  difference" → `mode`)*. Give the trade-off context (the demo is dark;
  combatden Duck Groove and smoketest are light; a gym aesthetic often leans
  dark). Recommend from the archetype but require an explicit pick — a wrong
  guess here silently inverts the entire palette. "Explain the difference"
  loops a short explanation then re-asks.
- **C2 — Colour mood + hue family** *(open, bounded → `description`)*. The
  emotional job of colour, the rough hue family/families for the primary, and
  saturation intent (vivid-confident vs gently-desaturated). Offer researched
  mood↔hue pairings tied to the archetype. Describe families and intent, never
  values.
- **C3 — Accent intent** *(open, one sentence → `description`)*. The accent's
  role and feel, in words; it must read as a clearly distinct hue from the
  primary. No values.
- **C4 — Background / text character** *(open, short → `description`)*. Tell
  the user the pipeline keeps background near-extreme but with elevation
  headroom and text above AA, so they describe *character* only ("warm
  near-white like soft oat paper, not clinical pure white"; "soft friendly
  deep slate, warmer than harsh pure black") — never lightness numbers. This
  question teaches the constraint as it asks.

After C1–C4, **compose** `colors_direction.description` in the house
bullet style (Primary / Background / Text / Accent lines) and **show the
assembled prose back verbatim for approval or edit** before proceeding —
composing prose from fragments is itself an inference, so it is gated.

## Step 3 — Assemble, validate, write, confirm

1. **Assemble** the full `customization.yaml`: the two top-level blocks
   (`design_direction:` then `colors_direction:`), multi-line prose as literal
   block scalars (`|`) exactly as the existing briefs do. Show the **entire**
   YAML to the user in the conversation.
2. **Round-trip validate** before writing. Per `CLAUDE.md` Dependencies
   (the `poetry run` mandate — never bare `python3` / `.venv/bin/*`), validate
   by importing the real model from the package root:
   ```
   poetry run python -c "import sys,yaml; from schema.customization import Customization; Customization.model_validate(yaml.safe_load(open(sys.argv[1])))" <path>
   ```
   On failure, surface the Pydantic error **verbatim**, name the offending
   field, and loop back to the relevant question. Never auto-patch.
3. **Ask where to write** *(`AskUserQuestion`)*: an existing `apps/<app_id>/`
   dir (overwrite — confirm explicitly) or a new `apps/<new_id>/` directory
   (the user supplies the id; remind that a matching architect-owned
   `app.yaml` must exist there for a pipeline run to work — you do not create
   it). Never default the location.
4. **Write only after explicit approval of both content and path.** Write
   `apps/<app_id>/customization.yaml`. Re-run the validation against the
   written file as a final integrity check. Confirm with the absolute path
   written and a one-line recap (name, mode, app id).

## Anti-patterns

- Never put a hex, oklch, RGB, HSL, or any numeric colour value in the brief.
- Never assume or auto-fill any answer; never "I'll proceed with X"; never
  expand a terse answer into prose without showing it back.
- Never invent fields — only the five writable fields exist (`extra="forbid"`).
- Never write or edit `app.yaml`, pipeline code, or any file other than the
  chosen `apps/<app_id>/customization.yaml`.
- Never invent slots or describe moments the app doesn't have.
- Never skip the `poetry run` round-trip validation.
- Never copy an existing brief's content; calibrate to its voice only.
- Never use bare `python3` / `.venv/bin/*` — `poetry run` only.
- Never force prose into a multiple-choice, or a multiple-choice onto
  something that needs the user's own words.

## Quick checklist

1. Read the target `app.yaml`; grounded questions in its real slots.
2. Calibrated voice from existing briefs without copying them.
3. Asked the brand questions deeply (archetype, essence, story, voice,
   mascot, visual system, hard nos), recommending options every time.
4. Kept colour at mood / hue-family / saturation / mode only.
5. Showed the assembled colour prose back for approval.
6. Showed the full assembled YAML.
7. `poetry run` round-trip validation passed.
8. User explicitly chose the write path.
9. Confirmed with the absolute path + a one-line recap.
