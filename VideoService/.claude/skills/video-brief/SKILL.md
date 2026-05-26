---
name: video-brief
description: >-
  The single end-to-end gym-video pipeline for the CustomYoutubeService demo:
  author the brief, then optionally fetch the videos, audit them, and generate
  branded class images — one skill orchestrates everything. Use it whenever the
  user wants to set up YouTube videos / a video feed / class images for a
  company, says "create a video brief", "set up youtube searches", "what videos
  should we pull for <company>", "fetch the videos", "audit the videos", "remove
  negative videos", "set up class images", or wants to revise an apps/<app_id>/.
  PHASE 1 (always) — a LEAN, one-question-at-a-time interview about ONLY the GYM
  (company name as open text, gym type, persona, culture, what it teaches/
  believes/rejects, priority channels), recommending researched options but
  never picking; from those facts it DERIVES the video output, composes
  videos_desc + avoid_desc (shown for approval), drafts exactly 5 query-only
  search prompts spanning a broad range of content types (WITHOUT showing the
  queries), Pydantic-validates, and writes apps/<app_id>/videos_config.yaml.
  Then it OFFERS, each gated by a yes/no, PHASE 2 fetch (run the YouTube Data API
  batch -> videos_output.yaml; warns about ~1-2k quota units), PHASE 3 audit
  (remove videos that are negative/contrarian about the gym's discipline or match
  avoid_desc, context-lean via the audit list/remove scripts, confirmed before
  removing), and PHASE 4 class images (derive + approve 4 on-brand class names,
  find and VISUALLY verify a horizontal image for each, write
  apps/<app_id>/class_output.yaml). Trigger on anything youtube-search /
  video-discovery / gym-content / class-image shaped. Writes only YAML under
  apps/<app_id>/; never edits schema or API code.
---

# Video pipeline — brief → fetch → audit → class images

This is the **one skill that drives the whole gym-video setup**, in four phases:

1. **Author the brief** (always) — interview the gym, write `videos_config.yaml`.
2. **Fetch** (offer) — run the YouTube Data API batch → the per-app feed
   (`videos_output.yaml` manifest + one `videos/<id>.yaml` per video).
3. **Audit** (offer) — remove videos that work against the gym.
4. **Class images** (offer) — write `apps/<app_id>/class_output.yaml`: 4 on-brand
   class cards (name + horizontal image).

Phase 1 is the heart of the skill; Phases 2–4 are each **offered, never assumed** —
ask a yes/no and stop the chain the moment the user declines (they can run later).
All four phases below; the bulk of this doc is Phase 1 because it's the hardest.

## Phase 1 — author videos_config.yaml

You produce a `videos_config.yaml` that round-trips against the `VideosConfig` Pydantic
model (`schema/videos_config.py`). It captures, for a single company, the business and
the *kinds* of YouTube videos worth surfacing — plus a curated list of **exactly 5
search prompts** that span the content spectrum.

This brief is *intent plus concrete searches*. The searches are **query-only** — the
literal queries the Phase 2 batch feeds to the YouTube Data API. Your job is to make the
search set sharp, varied, and genuinely tuned to the company, not a flat template.

## The writable surface (the whole of it)

From `schema/videos_config.py` — all models are `extra="forbid"`, so **any other key
fails validation**:

- `company_name` — display name of the business (non-empty)
- `type` — the business / niche type, e.g. "Muay Thai gym", "specialty coffee roaster"
  (non-empty)
- `videos_desc` — prose: the kinds of videos worth surfacing for this company (non-empty)
- `avoid_desc` — prose: **within-niche** content to exclude (non-empty). A
  downstream classifier judges each video against this text using **only the video's title
  and description**, so every avoid must pass **two tests**:
  1. **Specific** — a concrete thing, not an abstract category. "fake master channels",
     "self-defense fantasy", "McDojo content", "bad technique" are all **too broad** — they
     name a vibe, not a video. Name the actual technique, claim, phrasing, or format.
  2. **Verifiable from a title/description** — something the classifier could actually spot
     in the title or description. "low-credibility instructors" isn't verifiable from a
     title; *"videos claiming one move guarantees a street-fight win"* or *"titles like
     'deadliest [technique]' / 'the ONE move that always works'"* is.

  Good (BJJ): "videos teaching heel hooks with no mention of control/tapping safety;
  titles promising a guaranteed street-fight finish; 'BJJ is useless in a real fight'
  debate/reaction videos." Bad (useless): "fake masters, McDojos, self-defense fantasy,
  bad mechanics." And **not** obviously-unrelated topics (a Muay Thai gym excluding
  "cycling videos" is pointless). When in doubt, ask: *could I tell this video matches just
  by reading its title and description?* If not, rewrite it until you can.
- `searches` — a list of **exactly 5** items, each with just:
  - `query` — the literal YouTube search prompt (non-empty)
- `priority_channels` — an optional list of channels the company wants prioritized
  (their own and/or ones they like): free-form strings — a name, `@handle`, or URL. May
  be empty. A later step resolves and weights these deterministically; here you just
  capture what the user names.

Six top-level fields. Never invent a seventh. The model accepts **1–20** searches; for
now this skill always writes **exactly 5**.

### Asked vs. derived — the core split

**Interview the user about the GYM, not about videos.** You ask only for facts about the
business — its `company_name`, its `type`, who it's for, its culture, what it teaches,
what it believes and what it rejects, and **which channels it wants prioritized**
(`priority_channels`). The user should never have to think about YouTube genres, search
terms, or "content strategy."

Then **you derive the rest** from those gym facts:

- `videos_desc` and `avoid_desc` — you compose them, then **show them back to the user at
  the end for approval / revision** (the descriptions gate — see the final step).
- `searches` — you draft all 5 yourself and **do NOT show them for approval**;
  composing a well-spread set from the gym's identity is your job.

So: ask for the gym facts (incl. channels), derive the video fields, get the two
*descriptions* approved, write the searches un-gated.

The nine `VideoType` genres span: `educational`, `analysis`, `entertainment`, `news`,
`interview`, `vlog`, `professional`, `clips`, `memes`. See `references/video_types.md` for
what each means and example search shapes.
**`professional` means pros/elite competitors performing the craft at the top level**
(e.g. pro fight footage, championship play) — NOT corporate / high-production video.

## Operating principles (load-bearing)

### 1. No assumptions

The package rule (`CLAUDE.md`), verbatim: *"When a decision has more than one reasonable
answer, ask and wait for the user's explicit response. Never assume,
recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is
encouraged; making the choice for the user is not."*

This applies to the **gym facts you ask for** (type, culture, beliefs, persona,
priority channels): every question offers 2–4 researched options (or a multi-select),
then the user picks or free-writes via the tool's **Other** field. You never fill a gym
fact from inference and never say "I'll go with X unless you object."

The **video output** is derived, with a split on review:
- `videos_desc` / `avoid_desc` — you infer them from the gym facts, then show them back
  for the user's approval before writing (the descriptions gate).
- `searches` — you infer and write the query strings without an approval gate (the user
  asked for exactly this).

The shape is: ask for the inputs, derive the outputs, get the two descriptions approved.

### 2. One question at a time, multiple-choice by default

**This is absolute.** Two hard rules, no exceptions:

- **One question per turn.** Never put more than one question in a single
  `AskUserQuestion` call, and never send two questions in one message. Ask, wait, then
  ask the next.
- **Multiple-choice / multi-select `AskUserQuestion` by default.** The lone exception is
  the **first question, the company name**, which is a plain open-text prompt (people
  already know their company's name). Every *other* gym question is an `AskUserQuestion`.
  Free expression still happens — through the tool's automatic **Other** option.

### 2a. Never think out loud

Output **only** text the end user wants to read. No narrating your reasoning, no "let
me…", no "now I'll…", no meta commentary about which step you're on. Ask the question,
react briefly to the answer, move on. It should read like a sharp human consultant, not a
model describing its own process.

### 3. Lean budget: ~8–10 information-gathering questions

Be ruthless. You have **about eight to ten** information-gathering questions for the
whole interview — treat each as expensive. Consolidate related dimensions into one
multi-select rather than spreading them across several single-selects.

What does **not** count against the budget: unavoidable **mechanics** (which company,
edit-vs-replace, write path).

You **may** exceed the budget when the *user* drives it — they want to tell you more about
the gym, keep refining, or open a new dimension themselves. Never exceed it for your own
thoroughness.

### 4. Go broad first, narrow at the end — and never assume

This is the single most important interview behaviour, and the easiest to get wrong. You
build a search set tuned to *this* gym by understanding the gym — and you get there by
**starting wide and tightening as confidence grows**, not by firing narrow, presumptuous
questions up front. Two failure modes to police hard:

**Assuming which kind of gym it is.** A boxing gym can be playful, social and
beginner-friendly just as easily as it can be a hardcore fight team; a yoga studio can be
competitive and intense. Never let an early option bank presume the answer. Open with the
widest framing (what is this gym, who's it for, what's the overall personality?), let each
answer collapse the possibility space, and only ask the narrower, more specific questions
once the broad ones have made them relevant. **Get precise at the END, not the start.**
The question plan below is a guide, **not a script** — never read it in order; rebuild
every question's options from what the user has actually said so far. If you're about to
offer an option that only makes sense under an assumption the user hasn't confirmed, stop
and ask the broader question first.

**Same-theme options that aren't really a choice.** Every option inside a question must be
a genuinely *distinct* alternative pointing a different direction, so the user's pick
actually tells you something. If a multi-select is five flavours of the same idea, the
user just ticks all of them and you have learned nothing — and you've made it *feel* like
they're choosing everything every time. That is a symptom of a question that's too narrow
or has already assumed the answer. Offer real branches (e.g. "hardcore fight team" vs
"welcoming and social" vs "technical and studious" vs "competition-driven"), not a
checklist of synonyms. Each answer should meaningfully narrow what the next question asks.

### 5. Spread the searches broadly across the content spectrum

The single most important output behaviour: the 5 queries must be written to surface
content spread **as broadly as possible across the nine `VideoType` genres** — no one
kind should dominate what comes back. Breadth lives in the *queries themselves*: word
them so the set reaches across the five clusters — teach (educational/analysis), enjoy
(entertainment/clips/memes), inform (news), human (vlog/interview), and peak
(professional). With only 5 queries you **can't** target every genre, so aim a distinct
query at **5+ of those content types**. Do not let the gym's "main thing" (e.g. technique
for a how-to gym) crowd out the rest — the value of the set is its breadth.

## Step 0 — Locate the company

1. Ask which company this brief is for (mechanics, not an interview question).
   `AskUserQuestion` listing the discovered `apps/<app_id>/` dirs (run `ls apps/`) plus a
   "new company" option.
2. **Existing company:** if a `videos_config.yaml` already exists there, read it and ask
   the user explicitly (one `AskUserQuestion`, options: edit / replace from scratch).
3. **New company:** the user supplies a snake_case `app_id` for the directory.
4. Read `apps/combatden/videos_config.yaml` and `references/video_types.md` for **voice
   and structure calibration only** — the house register (a tight `videos_desc`, a sharp
   `avoid_desc`, concrete `query` strings). Never copy their content; the company is the
   user's.
5. Summarize back (prose, not a question): the company id and that you'll ask a few quick
   questions about the gym, then build the video list for them.

## The interview — all about the gym (~6–8, one at a time)

You are interviewing the user about their **business**, never about videos. Every
question is a fact about the gym; the video output is yours to derive afterward
(see the writable-surface split). This is the recommended set, not a rigid script and
**not a numbered sequence** — never label questions "Question 3 of 10". Re-derive each
question from the answers so far (principle 4). Keep the **bold** ones.

### Mechanics first (uncounted)

- **Company name** *(open text → `company_name`)*. The very first question, and the
  **only** plain-text prompt. Just ask what the gym is called.
- **Gym type** *(single-select → `type`)*. Right after the name, ask what kind of gym /
  business it is (e.g. Muay Thai, BJJ, CrossFit, yoga studio, climbing gym). Offer
  researched options tuned to anything the name hints at, plus **Other**. Use the answer
  to pre-tune every later option bank.

### About the gym (weight the budget here)

Ordered **broadest → most specific** on purpose (principle 4). Open wide, let each answer
collapse the space, and only get precise near the end. This is a guide, not a script —
re-derive every question and its options from what the user has already said, and make
every option a *distinct branch*, never five shades of one idea.

- **Overall personality / vibe** *(single-select, the broad opener)*. The widest
  question: what's this gym fundamentally like? Offer genuinely divergent branches —
  e.g. hardcore fight-team intensity vs welcoming-and-social vs technical-and-studious vs
  family-friendly vs competition-driven vs laid-back. **Do not assume** which it is from
  the gym type (a boxing gym can be any of these). Whatever they pick collapses the space
  for everything below; rebuild the later options around it.
- **Target persona** *(single- or multi-select)*. Now narrower: who is the gym *for* — its
  ideal member (complete beginners, committed hobbyists, competitors, parents signing up
  kids, busy professionals)? Shape these options around the personality they just chose.
- **What it teaches / what it believes** *(single- or multi-select → its philosophy)*.
  Narrower still: what does the gym stand for and emphasize — its approach, values, the
  way it thinks the craft should be done (e.g. "real fight discipline, fundamentals
  first", "movement for longevity, no ego", "strength through consistency")? This is the
  heart of the brief. Derive the options from the vibe + persona already given.
- **What it rejects / doesn't believe** *(single- or multi-select → its anti-philosophy)*.
  The sharp flip side — the approaches, framings, or bad habits *within the field* the gym
  pushes back on. Let the user answer in their **own natural language** — broad is exactly
  what to expect ("McDojo stuff", "ego lifting", "self-defense fantasy"). You **may and
  should** ask a clarifying question to understand what they *mean* — "when you say McDojo,
  is it the belt-selling, the unrealistic technique, or the marketing?" — that's
  understanding their values, which is the whole point of the interview. What you must
  **never** do is ask them about **videos or titles** — never "what should we exclude" or
  "what would such a video be called." They think about their gym and what they dislike,
  never about video metadata; turning their meaning into concrete, title-verifiable avoids
  is **your** job at the derive step. Keep it to in-world distinctions, not
  obviously-unrelated topics.
- **Priority channels** *(open text → `priority_channels`, optional)*. Ask whether there
  are specific YouTube channels they want prioritized — **their own channel and/or
  channels they like and trust**. Free-form: a name, `@handle`, or URL; collect as many
  as they give. Make clear it's optional — "skip" / "none" is a fine answer, and an empty
  list is valid. Don't pad it with suggestions of your own; capture only what they name.
  (These get resolved and weighted deterministically in a later step — here you only
  record them.)

## Final step — Derive, approve descriptions, validate, write

Once you understand the gym, you build everything else with **no further video questions**.

1. **Derive `videos_desc`** from the gym's type, persona, culture, and philosophy — prose
   describing the kinds of videos worth surfacing for *this* gym, in the house voice
   (tight, concrete — see the combatden example).
2. **Derive `avoid_desc`** — this is **your reasoning work, not the user's**. They handed
   you a natural-language want ("no McDojo stuff", "nothing that says BJJ is useless");
   silently translate each one into the concrete, title/description-verifiable form a
   classifier can actually act on (it sees only the title + description). Reason it through:
   *what would a video the gym hates actually look like — what claim, phrasing, technique,
   or format would show in its title or description?* e.g. "McDojo" → "videos selling
   fast-track belt promotions or guaranteed-rank programs"; "self-defense fantasy" →
   "titles promising one move guarantees a street-fight win / 'deadliest [technique]'";
   "BJJ is useless" → "'BJJ doesn't work in a real fight' debate/reaction videos". Every
   avoid must be **specific AND verifiable from a title/description** (see writable-surface
   rules); drop anything that survives only as a vibe. The user never sees or thinks about
   this translation — they just get an `avoid_desc` that captures what they meant.
3. **Descriptions gate.** Show the composed `videos_desc` and `avoid_desc` back to the
   user (one `AskUserQuestion`) and get approve / revise. This is the **only** content
   approval — the search queries are *not* shown (next step). Loop here until approved.
4. **Draft exactly 5 searches** yourself. Write concrete `query` strings — real phrases
   someone would type into YouTube, specific to this gym's world — **spread broadly across
   the content spectrum** (principle 5). Do **not** show the queries to the user for
   approval, and do not ask them to review or pick them — composing a well-spread set
   from the gym's identity is your job.
5. **Assemble** the full `videos_config.yaml`: the four scalar/prose fields, then the
   `searches:` list (each item just a `query`), then `priority_channels` (the channels the
   user named, verbatim; omit the key or use `[]` if none). Use literal block scalars
   (`|`) for the multi-line `videos_desc` / `avoid_desc`, exactly as the combatden example
   does.
6. **Round-trip validate** before writing. Per `CLAUDE.md` (the `poetry run` mandate —
   never bare `python3` / `.venv/bin/*`):
   ```
   poetry run python -c "import sys,yaml; from schema.videos_config import VideosConfig; VideosConfig.model_validate(yaml.safe_load(open(sys.argv[1])))" <path>
   ```
   On failure, surface the Pydantic error **verbatim** and fix it yourself (a common one:
   not exactly 5 searches) — re-draft and re-validate; never drag the user into a query
   you mis-wrote.
7. **Confirm the write path** (`apps/<app_id>/videos_config.yaml`) via `AskUserQuestion`;
   never default the location.
8. **Write once the descriptions are approved and the path is confirmed.** Re-run the
   validation against the written file as a final integrity check. Confirm with the
   absolute path written and a one-line recap (company name, type, search count, genres
   evenly covered, and how many priority channels were captured).

## Anti-patterns

- Never interview the user about videos, genres, search terms, or "content strategy" —
  ask only about the **gym** (type, persona, culture, what it teaches/believes, what it
  rejects) and derive the video output yourself.
- Never ask more than one question in a turn. Every gym question is multiple-choice /
  multi-select except the first, the company name, which is open text.
- Never number the questions to the user ("Question 3 of 10") — just ask.
- Never assume which kind of gym it is from its type — open with the broadest framing and
  let the answers narrow it; get precise only at the end (principle 4).
- Never offer a multi-select whose options are all the same theme (the user just ticks
  everything and you learn nothing) — every option must be a distinct branch pointing a
  different direction (principle 4).
- Never read the question plan in order as a script — rebuild each question and its
  options from what the user has already said.
- Never think out loud or narrate your process; output only what the user wants to read.
- Never write more or fewer than **exactly 5** searches.
- Never cluster the searches in one or two kinds of content — word the queries to surface
  a spread **broadly** across the nine `VideoType` genres, reaching 5+ distinct content
  types (principle 5). Don't let the gym's main thing crowd out the rest.
- Never write vague `query` strings ("good videos", "cool stuff") — every query must be a
  concrete phrase someone would actually type into YouTube.
- Never fill `avoid_desc` with obviously-unrelated topics (a Muay Thai gym excluding
  "cooking videos").
- Never write **vague / abstract** avoids — "fake masters", "McDojo content", "self-defense
  fantasy", "bad technique", "low-credibility instructors" are useless: they name a vibe,
  not a video, and a classifier reading only a title + description can't act on them. Every
  avoid must be **specific AND verifiable from a title/description** (the concrete claim,
  phrasing, technique, or format you'd actually see). Test each one: "could I tell a video
  matches just from its title and description?" — if no, rewrite it.
- Never invent the `professional` genre as corporate/high-production — it means pros
  performing the craft at the top level.
- Always show `videos_desc` and `avoid_desc` back for approval at the end (the
  descriptions gate); never write the file without that approval.
- Never show the search **queries** to the user for approval or gate the write on them —
  derive them from the gym facts and write them.
- Never pad `priority_channels` with channels the user didn't name, and never make it
  required — it is optional and may be empty; capture only what they give, verbatim.
- Never assume or auto-fill a **gym fact** (incl. priority channels) — those you always
  ask for. (The video fields are derived: descriptions get approved, searches don't.)
- Never invent fields — only the six writable fields exist (`extra="forbid"`).
- Never write or edit schema, API, or any file other than the chosen
  `apps/<app_id>/videos_config.yaml`.
- Never skip the `poetry run` round-trip validation, and never use bare `python3` /
  `.venv/bin/*`.
- Never copy the combatden example's content; calibrate to its voice only.

## Quick checklist

1. Opened with the open-text company name, then the gym-type question, then asked only
   about the gym — **broadest first** (overall personality/vibe), narrowing to persona,
   philosophy, what it rejects, and priority channels.
2. Re-derived each question's options from the user's earlier answers — never read the
   template in order, never assumed which kind of gym it is, and made every option a
   distinct branch (not five shades of one theme).
3. Asked ONE question at a time (no numbering, no thinking out loud), every gym question
   after the name a multiple-choice / multi-select `AskUserQuestion`, within ~6–8
   questions; never asked about video genres or search terms.
4. Captured `priority_channels` (their own and/or liked channels) verbatim — optional,
   empty if none, not padded with my own suggestions.
5. Derived `videos_desc` and `avoid_desc` from the gym facts (avoid = the "what it
   rejects" answer), in the house voice, and **showed them back for approval**.
6. Drafted **exactly 5** concrete `query` strings, spread **broadly** across the nine
   `VideoType` genres (5+ distinct content types) — without showing them for approval.
7. `poetry run` round-trip validation passed (count == 5).
8. User explicitly chose / confirmed the write path.
9. Confirmed with the absolute path + a one-line recap.

---

# Phases 2–4 — the rest of the pipeline (each OFFERED, never assumed)

After the brief is written, walk the user through the remaining phases. **Offer each
with a yes/no `AskUserQuestion`**; if they decline a phase, skip it and move on (they
can re-run the skill later). Always carry the `<app_id>` forward.

## Phase 2 — fetch the videos (offer)

Ask whether to fetch now. **Warn first:** it calls the YouTube Data API (~1–2k quota
units of the 10k/day free allowance) and needs `YOUTUBE_API_KEY` in `.env`. If yes:

```
make youtube APP_ID=<app_id>
```

Report the video + quota counts it prints. If the user declines, skip Phase 3 (nothing
to audit) and go straight to Phase 4.

## Phase 3 — audit the fetched videos (offer; only if Phase 2 ran)

Remove videos that work against the gym — **context-lean**: reason over a compact title
list, never the whole `videos_output.yaml`.

**What to remove:** (1) videos negative/contrarian about the gym's discipline or focus
(e.g. "why muay thai doesn't work"); (2) videos matching the brief's `avoid_desc` (bad
technique as gospel, low-credibility figures, fake masters); (3) **cross-discipline
comparison videos** that pit the gym's discipline against another style and ask which to
pick — "X vs Y", "which is better", "difference between X and Y", "which one are you
choosing" (e.g. "Kickboxing vs Muay Thai: which do you choose?"). These advertise rival
disciplines and nudge prospects elsewhere, so they work against the gym even when the
content is neutral. **Keep** videos that merely teach the gym's discipline alongside
another ("5 moves for defense in Muay Thai *and* Kickboxing") and genuine cross-style
*fight footage* unless the title frames it as a "which is better" pitch — that line is a
judgment call, so surface borderline ones to the user rather than removing silently. When
unsure, **keep** — removal must be high-confidence.

1. Get the compact list (do NOT open `videos_output.yaml` yourself):
   ```
   poetry run python -m scripts.youtube_batch.audit list --app-id <app_id>
   ```
   Each line is `<video_id>\t<title>\t<channel>`.
2. Judge each title against the rubric (`videos_desc` / `avoid_desc`, already in hand
   from Phase 1). Collect the `<video_id>`s to remove + a one-line reason.
3. **Confirm before removing** — show the proposed removals (title + reason) via
   `AskUserQuestion`; drop any the user deselects.
4. Remove the confirmed ids in one call:
   ```
   poetry run python -m scripts.youtube_batch.audit remove --app-id <app_id> \
       --ids id1,id2,id3 --reason "negative about <discipline> / avoid_desc"
   ```
   This deletes the dropped videos' per-video files (the API serves the clean set
   immediately) and logs the removed videos + reasons to `videos_output.removed.yaml`
   (recoverable). Report removed-vs-kept and the removed titles.

## Phase 4 — branded class cards (offer)

Replace the mobile app's hardcoded class cards with on-brand ones. Writes
`apps/<app_id>/class_output.yaml` — **exactly four** class cards round-tripping the
`ClassOutput` model (`schema/class_output.py`). Each card has: `name`, a horizontal
`image_url` (class image), a `description`, and the instructor (`instructor_name`,
`instructor_bio`, `instructor_image_url` headshot).

**Where each field comes from:**
- `name` + `description` — **you derive** from the gym (Phase 1 `type`), shown for
  approval.
- `instructor_name` / `instructor_bio` / `instructor_image_url` — depends on the brief:
  - **Real-gym brief (default):** **real gym staff data you cannot invent or scrape.**
    Ask the user for each (a headshot URL too, or they can skip and you use a neutral
    placeholder). Never fabricate a real person's bio against a real, named gym.
  - **Demo / template profile:** when the brief is a demo, template, or
    discipline-archetype with **no real gym behind it** (the user says so, or it's
    clearly a stock vertical like `bjj` / `boxing` rather than a named business), you
    **may fabricate** plausible instructor names + bios without asking — mark the file
    with a comment that the instructors are placeholders. The `smoketest` profile is the
    reference for this. The image rule does **not** relax: every headshot is still a
    real, downloaded-and-viewed photo (reusing a small verified portrait pool across
    demo profiles is fine).
- `image_url` — the class background image, **you find and visually verify**.

Steps:
1. **Derive + approve 4 class names + descriptions.** From the gym `type`, propose four
   on-brand class names (e.g. Muay Thai → Fundamentals, Clinch, Pad Work, Sparring) with
   a one-line description each. Show via `AskUserQuestion` for approval / edits.
2. **Collect the instructor per class** — ask the user for name and a short bio (real
   gym staff data; don't invent it). If they give a headshot URL, validate it like any
   other image (step 3); otherwise source one the same way.
3. **Find + VISUALLY verify EVERY image — no exceptions.** This applies to all four
   class images AND all four instructor headshots. Never write a URL you have not
   downloaded and looked at. The procedure for each image:

   a. **Source candidates from Wikimedia Commons** (stable, hotlinkable, licensed —
      avoid random-placeholder services like picsum, which return unrelated photos). Hit
      its API and pull direct `upload.wikimedia.org` URLs:
      ```
      curl -s -A "CombatDen/1.0" "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=<query>&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url|size&iiurlwidth=1280&format=json"
      ```
      Use `thumburl` (the `iiurlwidth` thumb) for big class images; for headshots prefer
      portrait-orientation results. Query terms: the class + discipline ("muay thai
      clinch", "thai pads") for class images; a fighter/coach portrait term for headshots.
   b. **Download** the candidate to a temp file:
      `curl -s -A "CombatDen/1.0" "<url>" -o /tmp/cand.jpg` (a `<!DOCTYPE html>` body
      means a bad thumb size — use a size the API returned, or the original file URL).
   c. **VIEW it** — `Read` `/tmp/cand.jpg` and actually look. Confirm: (i) class images
      are **horizontal** (wider than tall); (ii) the image truly **is the thing** — a
      class image shows that activity in the discipline, a headshot shows a real person
      (ideally a martial artist) and reads as a coach portrait; (iii) it's clean — no
      watermark, logo, heavy text, collage, or AI-slop, and not an unrelated/wrong-subject
      photo.
   d. If it fails any check, pick another candidate and repeat. Only a URL that passed
      (c) goes in the YAML.
4. **Write** `apps/<app_id>/class_output.yaml`:
   ```yaml
   company_name: <from the brief>
   app_id: <app_id>
   classes:
     - name: <class 1>
       image_url: <verified horizontal url>
       description: <one-liner>
       instructor_name: <from the user>
       instructor_bio: <from the user>
       instructor_image_url: <verified headshot url or placeholder>
     # ...exactly four
   ```
5. **Round-trip validate** (per the `poetry run` mandate):
   ```
   poetry run python -c "import sys,yaml; from schema import ClassOutput; ClassOutput.model_validate(yaml.safe_load(open(sys.argv[1])))" apps/<app_id>/class_output.yaml
   ```
6. Report the four classes and that `GET /apps/<app_id>/classes` now serves them.

> **Known limitation (TODO):** hotlinked internet images rot, can be hotlink-blocked,
> and carry licensing risk on a customer-facing screen. The durable answer is owned /
> hosted images (generated via CustomizationService, or gym-uploaded). This is the
> interim brand-match step.

## Pipeline anti-patterns

- Never run Phase 2 / 3 / 4 without offering first — each is opt-in.
- Never run the fetch (Phase 2) without warning about quota cost.
- Never remove videos (Phase 3) without showing the list and getting a yes.
- Never write ANY `image_url` (class or instructor headshot) you haven't downloaded and
  **viewed** — every single image is validated by eye (Phase 4 step 3).
- Never use random-placeholder image services (picsum, placekitten, etc.) — they return
  unrelated photos. Source real, relevant images (Wikimedia Commons) and verify them.
- Never edit the feed files by hand (the `videos_output.yaml` manifest or any
  `videos/<id>.yaml`) — go through the audit `remove` script.
