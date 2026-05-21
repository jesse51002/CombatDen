---
name: brand-brief
description: >-
  Interactively author a schema-valid customization.yaml brand brief for the
  AI customization pipeline. Use this skill whenever the user wants to onboard
  a new brand/app to the pipeline, write or rewrite a customization.yaml, says
  "set up a new app", "create a brand brief", "I have a new gym/business to
  customize", "draft the design direction", "fill in colors_direction", asks
  what to put in customization.yaml, or wants to revise an existing brief in
  apps/<app_id>/. This is a LEAN, question-driven interview: it asks a small
  set (≈10 max) of high-leverage questions, ONE at a time. It opens with an
  open-text gym-name question, then asks the gym type, then runs the brand
  interview as multiple-choice / multi-select AskUserQuestion prompts — the
  user's own wording always comes through the tool's free-write "Other" option.
  It recommends researched options for every question but never
  picks for the user, reads the chosen app's app.yaml to ground its questions
  in that app's real slots, keeps colour direction GENERAL (mood / hue family /
  saturation + light or dark mode — never hex or oklch) but ALWAYS asks about
  colour and ALWAYS gets the colour scheme approved, then assembles,
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
architect-owned and off-limits here). Your entire value is asking a few
**sharp** questions a blank file wouldn't — and refusing to answer them for the
user.

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

Every question offers 2–4 researched options (or a multi-select), then the user
picks or free-writes via the tool's **Other** field. You never fill a field
from inference, never say "I'll go with X unless you object," and never
silently expand a one-word answer into prose without showing the prose back for
approval.

### 2. One question at a time, multiple-choice by default

**This is absolute.** Two hard rules, no exceptions:

- **One question per turn.** Never put more than one question in a single
  `AskUserQuestion` call, and never send two questions in one message. Ask,
  wait for the answer, then ask the next. (The one allowed back-to-back run is
  the **confirmation gates at the very end** — see the final step.)
- **Multiple-choice / multi-select `AskUserQuestion` by default.** The lone
  exception is the **first question, the gym name**, which is a plain open-text
  prompt (people already know their gym's name — offering "naming formats" is
  busywork). Every *other* interview question is an `AskUserQuestion`; never use
  a bare plain-text prompt for them. Free expression on those still happens —
  through the tool's automatic **Other** option, and through the approval gates
  where you show composed prose back for edit.

### 2a. Never think out loud

Output **only** text the end user wants to read. No narrating your reasoning,
no "let me…", no "now I'll…", no meta commentary about which step you're on or
what you're about to do. Ask the question, react briefly to the answer, move
on. The interview should read like a sharp human consultant talking, not a
model describing its own process.

### 3. Lean budget: ≈10 information-gathering questions

Be ruthless. You have **about ten** information-gathering questions for the
whole interview — treat each as expensive and design it to earn its place.
Consolidate related dimensions into one multi-select rather than spreading them
across several single-selects. Drop any question whose answer you could
reasonably derive from the archetype and confirm later at an approval gate.

What does **not** count against the ~10:
- the **approval / confirmation gates** (showing the essence line, the colour
  prose, and the full YAML back as "approve or revise") — these are mandatory
  and separate;
- unavoidable **mechanics** (which app, edit-vs-replace, write path) — keep
  them minimal but they are not "interview" questions.

You **may** exceed ~10 when the *user* drives it — they reject your options,
want to keep refining, ask to go deeper, or open a new dimension themselves.
Never exceed it just to satisfy your own thoroughness.

### 4. Deep on brand, general on colour — but always ask colour

Within the lean budget, weight questions toward **brand identity** (archetype,
essence, story/contrast, voice, visual system, hard nos) over colour. Colour
stays at mood / hue-family / saturation-intent / mode level only — but it is
**never skipped**: you MUST ask about colour and you MUST get the assembled
colour scheme explicitly approved by the user before writing.

Tell the user *why* colour stays general, so the limit is not arbitrary: the
pipeline owns precise values and enforces rules a hardcoded colour would fight.
Cite `src/modules/colors/prompts/color_palette_rule.md` and the deterministic
contract enforced in `src/modules/colors/color_models.py` (the
`build_color_response_model` validator, `MIN_CONTRAST_AA = 4.5`):

- background & text must be low-chroma (≈0.003–0.04) with a faint brand tint,
  never pure grey/black;
- text must clear **WCAG AA ≥ 4.5:1** against the background;
- the **background lightness band**: near an extreme but held off it on both
  sides (dark L 8–30%, light L 86–90%) so the MobileApp client's translucent
  elevation veil has tonal room for cards/sheets to read (README TODO #1);
- **every** non-background colour (primary, accent, brand, highlight) may be
  rendered as text or an icon directly on the canvas, so it must clear AA
  against the background too — a vivid hue sitting at the canvas's own
  lightness fails.

A hex/oklch in the brief is ignored at best and fights these rules at worst.

**Never offer a colour option that is doomed to break this contract.** Every
mood↔hue option you put on the table must be *physically satisfiable* under the
rules above — the pipeline rejects a palette that isn't, and an option you
recommended turning into a validation error is your fault, not the user's.
Concretely: never offer a near-black/grey primary or accent in dark mode (or a
near-white one in light mode) that cannot clear AA against the canvas; never
offer "low-contrast", "washed-out", or "barely-there" *text*; never describe a
background as "pure black" or "pure white". If a brand genuinely wants a tone
that can't clear AA in a given role (e.g. a ghost watermark accent), name that
trade-off out loud and steer it to a role the contract permits — the rule has an
override for deliberately low-contrast *non-text* slots, quoted into that slot's
description — rather than smuggling it in as a normal pick.

### 5. Ground every question in the real app

Before interviewing, locate and read the target app's `app.yaml`. The brief
feeds *every* slot's prompt, so tailor questions to the slots that actually
exist. Name real slots back to the user in your option descriptions. Never
invent a slot; never write `app.yaml`.

### 6. Go broad first, then narrow — and adapt every question to the answers

**The question plan below is a guide, not a script.** The single most important
behaviour in this skill is to **shape each question from what the user has
actually said so far**, not to read the canned questions in order. After every
answer, rebuild the next question's options around that answer. If they say the
gym is playful and social, your voice and visual options must reflect a playful
brand — don't offer the intense-fighter options anyway because the template
listed them.

**Start broad, then reduce scope as your confidence grows.** Early questions
stay wide-open and assumption-free — a boxing gym can be fun, neon, and social
just as easily as it can be intense and hardcore; a yoga studio can be edgy.
**Never assume which kind it is.** Open with broad framing (what's the overall
vibe / personality?), let the answer collapse the possibility space, and only
then ask the narrower, more niche questions that have become relevant. Each
answer should make the next question more specific. If you find yourself about
to offer an option that only makes sense under an assumption the user hasn't
confirmed, stop and ask the broader question first.

This is the difference between an interview that feels bespoke and one that
feels like a form. Bias hard toward bespoke.

### 7. Stylised, never photorealistic

**Never recommend realistic / photoreal imagery.** Photoreal output is an
anti-pattern both for this pipeline and for app UI generally: the pipeline is
tuned for clean, stylised, iconographic assets (flat or 3D-stylised marks,
emblems, silhouettes, mascot-style renders), photorealism is hard for it to
produce reliably, and it reads wrong across the app's range — from tiny
ever-present tokens that must stay razor-legible to the celebratory heroes. So
when you compose visual-system, mascot, or anchor options, **do not offer
"realistic", "detailed", "photoreal", or "rendered-photo" as a style choice.**
Keep every option in stylised territory — emblem / crest, geometric mark,
mascot-style 3D, flat illustration, bold silhouette. If the user free-writes
that they want photorealism, flag plainly that the pipeline produces stylised
assets and redirect them to the closest stylised treatment; never write
"photorealistic" (or a synonym) into `long_desc`.

## Step 0 — Locate the app and read its app.yaml

1. Ask which app this brief is for (mechanics, not an interview question).
   `AskUserQuestion` listing the discovered `apps/<app_id>/` dirs (run
   `ls apps/`) plus a "new app" option.
2. **Existing app:** read `apps/<app_id>/app.yaml`. If a `customization.yaml`
   already exists there, read it and ask the user explicitly (one
   `AskUserQuestion`, options: edit / replace from scratch).
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
5. Summarize back (prose, not a question): app id, slot count, the kinds of
   moments the slots cover (celebratory heroes vs persistent tiny utility icons
   vs the brand anchor), and the colour slots with their roles. This framing
   primes every later question.

See `references/archetypes.md` for the full option banks the steps below draw
from.

## The lean question plan (≈10, one at a time)

This is the recommended set, not a rigid script and **not a numbered
sequence** — never label questions "Question 3 of 10" or similar to the user;
just ask the next one. Add, drop, reorder, or collapse questions as the app and
the user's earlier answers warrant, but keep the **bold** ones. Each is a single
`AskUserQuestion` (except the open-text name) — ask, wait, continue.

**Re-derive every question from the answers so far (principle 6).** Go broad
early, narrow as confidence grows, and rebuild each question's options around
what the user has already told you — never just paste the topics below in
order. The list names *what* to cover; the *options* are yours to compose live
and assumption-free.

**Do not confirm anything mid-interview.** All composed-prose approvals — the
essence line *and* the colour scheme — are held to the end and shown
back-to-back (see the final step). Confirming the essence in the middle wastes a
turn and, worse, locks wording before you have the voice, story, and visual
system that should shape it. Gather everything first, confirm at the end with
full context.

### Mechanics first (uncounted, deterministic)

- **Gym name** *(open text → `name`)*. The very first question, and the **only**
  plain-text prompt in the whole flow. Just ask what the gym is called — people
  know their own name; offering "naming formats" is busywork. Do not propose
  names.
- **Gym type** *(single-select, uncounted — temporary dev scaffold)*. Right
  after the name, ask the gym's discipline (e.g. BJJ / kickboxing / boxing / MMA
  / CrossFit / boutique-fitness / yoga-pilates). Keep the options tight and
  deterministic; this is a stand-in for a field the UI will eventually supply,
  so it does **not** count against the ~10. Use the answer to pre-tune every
  later option bank.

### Brand (weight the budget here)

- **Archetype** *(single-select → frames everything)*. The researched
  archetypes from `references/archetypes.md`, each a one-line descriptor, plus
  the implicit "Other" for a blend. Say it is a starting frame, not a box; if
  they blend, note which leads.
- **Essence** *(single-select → `short_desc`)*. Offer 2–3 example one-line
  phrasings derived from the archetype answer, in the house shape
  (*"[hook] — a [what it is] that [philosophy]."*). The user picks or edits via
  **Other**. **Do not confirm it now** — record the pick and move on; it gets
  approved with everything else at the end.
- **Story + contrast** *(single- or multi-select → `long_desc` ¶1)*. Bundle
  *who it's for* and *what it is explicitly NOT* (the contrast sharpens
  identity more than the positive). Multi-select of audience/positioning
  statements works well here; the failure modes the brand must avoid feed the
  hard-nos later.
- **Voice** *(single-select → `long_desc`)*. One question: each option is a
  tone (warm-encouraging / calm-unhurried / bold-confident / playful-bubbly /
  understated-premium / a calm-confident blend, etc.) and its description
  should carry the implied "never sounds like" so you capture register and
  anti-register in a single pick. Let **Other** hold the founder's own line.
- **Visual system** *(multi-select → `long_desc`)*. The deepest brand lever —
  but **one** multi-select question, not five. Offer a menu drawn from the
  archetype covering *feel*, *medium & materials*, *finish & light*, and
  *energy by role* (name the app's real persistent vs celebratory slots in the
  option text). The user ticks the traits that fit. Keep every trait stylised —
  never offer a "realistic / photoreal" option (principle 7). If a
  mascot/hero-symbol decision is live for this app's slots, fold it in as one
  option here rather than spending a separate question.
- **Hard nos** *(multi-select → `long_desc`)*. Explicit prohibitions. Seed the
  options from the failure modes named in the story/voice answers and the
  archetype's hard-nos; the user ticks all that apply and adds their own via
  **Other**.

### When the user names a mascot or a specific object — dig in, never invent

If the user picks (or free-writes) a **mascot, character, animal, or any
specific named object** as the brand anchor or a hero, they almost always have a
concrete picture in their head. **Do not** glide past it and let the prose
invent a random creature — that guarantees the generated image is not what they
meant. Spend one (or more, user-driven) follow-up `AskUserQuestion` to pin down
*what they actually mean*: which animal/character, its style (mascot-cartoon vs
emblem/crest vs bold silhouette — never photoreal, see principle 7), its pose or
attitude, what it's wearing or holding,
and how stylised it should be. Only once it is specific do you write
it into `long_desc`. The same applies to any "specific object" anchor (a
particular weapon, trophy, totem, etc.) — get the specifics, never assume.

### Colour (mandatory — ask, then get it approved at the end)

Open by stating to the user, in plain prose: **we are not picking exact colours
here**, and why (principle 4). Then:

- **Mode** *(single-select, `light` / `dark` → `mode`)*. Give the trade-off
  context (a gym aesthetic often leans dark; light reads open/approachable).
  Recommend from the archetype but require an explicit pick — mode silently
  inverts the whole palette. (Offer an "explain more" path via **Other** if
  they're unsure.)
- **Colour direction** *(single- or multi-select → `description`)*. Capture the
  primary's emotional job + hue family + saturation intent, the accent's feel
  (a clearly distinct hue from the primary), and the background/text
  *character* (warm vs cool near-extreme — never lightness numbers). Prefer one
  well-built multi-select of researched mood↔hue options tied to the
  archetype; only split into a second colour question if the user needs it.
  Describe families and intent, never values. Every option must be satisfiable
  under the contrast / lightness contract (principle 4) — never put a colour on
  the table that can't clear AA in the role you're proposing it for.

## Final step — Confirm composed prose, assemble, validate, write

Once every question is answered, run the **confirmation gates back-to-back**
(this is the one place consecutive questions are allowed). Each is composed
prose — an inference from fragments — so each is gated, but they come in an
unbroken run now that you have full context:

1. **Essence gate.** Show the chosen `short_desc` line back; approve or revise.
2. **Colour gate (mandatory).** **Compose** `colors_direction.description` in
   the house bullet style (Primary / Background / Text / Accent lines) and show
   the assembled prose back; approve or revise. Never write the file without
   this explicit colour approval.

Then:

3. **Assemble** the full `customization.yaml`: the two top-level blocks
   (`design_direction:` then `colors_direction:`), multi-line prose as literal
   block scalars (`|`) exactly as the existing briefs do. Show the **entire**
   YAML to the user and get explicit approval (an approval gate, not counted).
4. **Round-trip validate** before writing. Per `CLAUDE.md` Dependencies
   (the `poetry run` mandate — never bare `python3` / `.venv/bin/*`), validate
   by importing the real model from the package root:
   ```
   poetry run python -c "import sys,yaml; from schema.customization import Customization; Customization.model_validate(yaml.safe_load(open(sys.argv[1])))" <path>
   ```
   On failure, surface the Pydantic error **verbatim**, name the offending
   field, and loop back to the relevant question. Never auto-patch.
5. **Confirm the write path.** Usually it is the app chosen in Step 0
   (overwrite — confirm explicitly via `AskUserQuestion`). If it is a new
   `apps/<new_id>/` directory, the user supplies the id; remind that a matching
   architect-owned `app.yaml` must exist there for a pipeline run to work — you
   do not create it. Never default the location.
6. **Write only after explicit approval of both content and path.** Write
   `apps/<app_id>/customization.yaml`. Re-run the validation against the
   written file as a final integrity check. Confirm with the absolute path
   written and a one-line recap (name, mode, app id).

## Anti-patterns

- Never put a hex, oklch, RGB, HSL, or any numeric colour value in the brief.
- Never recommend realistic / photoreal imagery, and never offer a
  "realistic / detailed / photoreal" image style — the pipeline does stylised
  assets only (principle 7).
- Never offer a colour option that can't satisfy the contrast / lightness
  contract: no near-black/grey primary or accent in dark mode (or near-white in
  light mode) that fails AA, no low-contrast/washed-out text, no "pure
  black/white" background (principle 4).
- Never ask more than one question in a turn (the sole exception is the
  back-to-back confirmation gates at the end). Every interview question is a
  multiple-choice / multi-select `AskUserQuestion` except the first one, the
  gym name, which is open text.
- Never number the questions to the user ("Question 3 of 10") — just ask.
- Never think out loud or narrate your process; output only what the user wants
  to read.
- Never confirm composed prose (essence, colour) mid-interview — hold all
  confirmations to the end and run them back-to-back.
- Never invent a mascot/character/specific object the user named — ask follow-up
  questions to pin down exactly what they mean before writing it into prose.
- Never blow past ~10 information-gathering questions unless the user is the one
  driving the extra rounds (the gym-type question does not count).
- Never skip colour, and never write the file without the user explicitly
  approving the assembled colour scheme.
- Never assume or auto-fill any answer; never "I'll proceed with X"; never
  expand a terse answer into prose without showing it back.
- Never invent fields — only the five writable fields exist (`extra="forbid"`).
- Never write or edit `app.yaml`, pipeline code, or any file other than the
  chosen `apps/<app_id>/customization.yaml`.
- Never invent slots or describe moments the app doesn't have.
- Never skip the `poetry run` round-trip validation.
- Never copy an existing brief's content; calibrate to its voice only.
- Never use bare `python3` / `.venv/bin/*` — `poetry run` only.

## Quick checklist

1. Read the target `app.yaml`; grounded the option text in its real slots.
2. Calibrated voice from existing briefs without copying them.
3. Opened with the open-text gym name, then the deterministic gym-type
   question (uncounted), then the brand interview.
4. Went broad first, narrowed as confidence grew, and re-derived each
   question's options from the user's earlier answers — never just read the
   template in order, never assumed which kind of gym it is.
5. Asked ONE question at a time (no numbering, no thinking out loud), every
   interview question after the name a multiple-choice / multi-select
   `AskUserQuestion`, staying within ~10 information-gathering questions.
6. If a mascot / specific object was named, asked follow-ups to pin down exactly
   what the user meant before writing it — kept every style option stylised,
   never photoreal.
7. Weighted those questions toward brand; kept colour at
   mood / hue-family / saturation / mode only, and offered only colour options
   that can satisfy the contrast / lightness contract.
8. Held all composed-prose confirmations (essence, colour) to the end and ran
   them back-to-back; got explicit colour approval.
9. Showed the full assembled YAML back for approval.
10. `poetry run` round-trip validation passed.
11. User explicitly chose / confirmed the write path.
12. Confirmed with the absolute path + a one-line recap.
