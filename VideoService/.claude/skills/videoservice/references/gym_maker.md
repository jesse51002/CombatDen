# Make a gym

Author or edit one `VideoService/gyms/<gym_id>.yaml`. This guide is **only**
about the gym file — its disciplines, its theme, its videos config, its classes
and rewards. It says **nothing** about scraping or scanning; those are other
jobs (the gym just provides the `queries` the scraper reads and the
`specification` the scan judges against).

A gym is the unit of everything: a member browses gyms, picks one, loads the
**theme it carries**, and gets that gym's videos / classes / rewards. So a gym
file is what you write to bring a new gym (or a demo theme) online.

## The writable surface (the whole `Gym` model)

You author the fields below. The pipeline owns the rest (see "Do not touch").

```yaml
gym_id: vinyasa                       # stable id == the filename stem
gym_type: [vinyasa]                   # 1+ disciplines (the GymType enum)
theme: ZZUndoneVinyasaFlow            # the ThemeService design id this gym runs
videos:
  specification:
    videos_desc: >-                   # what the scan should KEEP (prose, ≥2 chars)
      Led full-length vinyasa classes, breath-paced, clear instruction,
      beginner-to-intermediate, filmed in a calm studio.
    avoid_desc: >-                    # what the scan should REJECT (prose, ≥2 chars)
      Talking-head philosophy, gymwear hauls, 30-second social clips,
      anything not an actual followable class.
  queries:                            # the searches the scraper runs for this gym
    - vinyasa flow full class breath led
    - beginner vinyasa yoga 30 minutes
  good_video_ids: []                  # ← scan fills this. Leave empty.
  rejected_video_ids: []              # ← scan fills this. Leave empty.
  scan_costs: []                      # ← scan appends here. Leave empty.
classes: null                         # optional branded class cards (below)
rewards: null                         # optional points-store reward cards (below)
```

### Field rules

- **`gym_id`** — snake_case, `^[a-z][a-z0-9_]*$`, and it MUST equal the filename
  stem (`gyms/vinyasa.yaml` → `gym_id: vinyasa`). It's a path-traversal guard too.
- **`gym_type`** — a non-empty **list** from the `GymType` enum
  (`schema/gym_type.py`, 76 disciplines). One discipline is the common case; use
  several only when the gym genuinely spans them (e.g. a spin+strength studio →
  `[spin_strength, indoor_cycling]`). The **first** entry is the primary — the
  gym browser derives the coarse `parent_gym_type` (Fighting/Yoga/…) from it.
  These disciplines are also the **candidate filter**: scan only considers pooled
  videos tagged with one of the gym's `gym_type`s.
- **`theme`** — one ThemeService design id (a folder name under
  `ThemeService/apps/combatden/`, e.g. `ApexMMA`, `ZZUndoneVinyasaFlow`). The
  theme→gym link IS this field; the gym browser serves it and the app loads it.
  The theme also supplies the gym's card art (its celebration image), derived by
  the API — you do **not** store an image url on the gym.
- **`videos.specification`** — the scan's criteria, as prose. `videos_desc` =
  what to surface; `avoid_desc` = what to reject. Both ≥2 chars, both required.
  Write them concretely — vague specs make the scan noisy.
- **`videos.queries`** — the YouTube searches that populate this gym's slice of
  the shared pool. Author them to cover the gym's disciplines well; the scraper
  reads them. Empty list is allowed (a gym that rides on others' queries), but
  then nothing new is fetched for it.
- **`classes` / `rewards`** — `null` until authored. Shapes below.

### `classes` — branded class cards (`ClassImage`)

Same shape AppManagement already renders. Each card:

```yaml
classes:
  - title: Sunrise Vinyasa
    image_url: https://…/sunrise.jpg     # landscape class image
    instructor: Maya Chen                 # ClassImage's instructor field
    # …match the current ClassImage model in schema/class_output.py
```

Confirm the exact `ClassImage` fields against `schema/class_output.py` before
writing — don't guess.

### `rewards` — points-store reward cards (`RewardCard`)

A reward card is a class card **minus the instructor** (rewards have none),
matching AppManagement's loyalty store (`LoyaltyReward`):

```yaml
rewards:
  - title: Bring a friend
    image_url: https://…/guest-pass.jpg  # landscape reward image (≥1 char)
    price_label: Free                      # paid on top of points: "Free", "30% off"
    points_cost: 250                       # ≥0
```

## Do not touch (the pipeline owns these)

- `good_video_ids`, `rejected_video_ids` — the **scan** overwrites these each run.
- `scan_costs` — the **scan** appends to these.

Author them as empty (`[]`) on a new gym and never hand-edit them after; they're
machine state.

## How to author — interview first, broad to narrow

When the user wants a new gym (or a fleshed-out one) and hasn't handed you every
field, **interview** — don't assume. Follow the skill's interview rules: **one
question per turn**, multiple-choice by default, **broad before narrow**, and
make the options genuinely distinct (not variations on one theme). Never fill a
field you can infer more than one reasonable answer for — ask.

A workable order (adapt, don't recite):

1. **What gym is this?** — the discipline(s) and the vibe, in the user's words.
   Map their answer to `gym_type` value(s); confirm the primary if several.
2. **Which theme does it run?** — the design id. If they don't know, offer the
   plausible matches from `ThemeService/apps/combatden/` for that discipline.
3. **What should its feed contain vs. exclude?** — turn this into
   `specification.videos_desc` / `avoid_desc`. Push for specifics.
4. **What searches feed it?** — draft `queries` from the discipline + spec; show
   them and let the user cut/add. (Don't invent filler queries.)
5. **Classes / rewards?** — only if the user wants them now; otherwise leave
   `null`. Get real titles/images/points from the user — don't fabricate.

## Write, then validate

1. Write `gyms/<gym_id>.yaml` with the surface above (empty pipeline fields).
2. **Validate** it round-trips against the `Gym` model before you're done:

   ```bash
   make gym-check GYM_ID=<gym_id>
   ```

   (Equivalently `poetry run python -m scripts.gym_maker.run check --gym-id <id>`.)
   This loads the file through the `Gym` Pydantic model via the service — a green
   check means the schema, the `gym_id`/filename match, and the enum values are
   all valid. Fix and re-run until clean. **Always `poetry run`**, never bare
   `python3` or `.venv/bin/*`.

After a gym exists with `queries` and a `specification`, the next jobs are the
**scraper** (fills the pool) and the **scan** (fills this gym's feed) — but those
are separate guides; don't do them here.

---

# The interview, in depth

The "How to author" sketch above is the shape; this is the substance. Authoring a
gym well is mostly a good interview about the gym, followed by *you* deriving the
video fields. The principles below are load-bearing — getting the interview wrong
produces a gym whose feed never matches what the owner actually wants.

## Asked vs. derived — the core split

**Interview the user about the GYM, not about videos.** You ask only for facts
about the business — what it is (`gym_type`), which `theme` it runs, who it's for,
its culture, what it teaches, what it believes and what it rejects. The user
should never have to think about YouTube genres, search terms, or "content
strategy."

Then **you derive** the video surface from those gym facts:

- `videos.specification.videos_desc` / `avoid_desc` — you compose them, then
  **show them back for approval / revision** (the descriptions gate, below).
- `videos.queries` — you draft them from the gym's identity. They're gym data the
  owner owns, so show them and let the user cut/add — but composing a
  well-spread set is your job, not theirs.

So: ask for the gym facts, derive the video fields, get the two *descriptions*
approved, draft the queries.

## Operating principles (load-bearing)

### 1. No assumptions

The package rule (`CLAUDE.md`), verbatim: *"When a decision has more than one
reasonable answer, ask and wait for the user's explicit response. Never assume,
recommend-and-proceed, or defer the choice unilaterally. Presenting researched
options is encouraged; making the choice for the user is not."*

This applies to every **gym fact** you ask for (discipline, theme, culture,
beliefs, persona): each question offers 2–4 researched options (or a
multi-select), then the user picks or free-writes via the tool's **Other** field.
Never fill a gym fact from inference; never say "I'll go with X unless you
object." The *video output* is derived — descriptions get approved, queries get
shown.

### 2. One question at a time, multiple-choice by default

**Absolute, no exceptions:**

- **One question per turn.** Never put more than one question in a single
  `AskUserQuestion`, and never send two questions in one message. Ask, wait, then
  ask the next.
- **Multiple-choice / multi-select by default.** The lone exception is the
  **first question, the gym's name**, a plain open-text prompt (people know their
  gym's name). Every *other* gym question is an `AskUserQuestion`; free expression
  still happens through the automatic **Other** option.

### 3. Never think out loud

Output **only** text the user wants to read. No narrating your reasoning, no "let
me…", no "now I'll…", no meta commentary about which step you're on. Ask, react
briefly, move on. Read like a sharp human consultant, not a model describing its
own process. Never number questions to the user ("Question 3 of 10").

### 4. Lean budget: ~8–10 questions

Be ruthless — you have **about eight to ten** information-gathering questions for
the whole interview; treat each as expensive. Consolidate related dimensions into
one multi-select rather than spreading them across single-selects. Mechanics
(which gym, edit-vs-replace) don't count. You **may** exceed the budget when the
*user* drives it (they want to tell you more) — never for your own thoroughness.

### 5. Go broad first, narrow at the end — and never assume

The single most important interview behaviour, and the easiest to get wrong. Two
failure modes to police hard:

**Assuming which kind of gym it is.** A boxing gym can be playful, social and
beginner-friendly just as easily as a hardcore fight team; a yoga studio can be
competitive and intense. Never let an early option bank presume the answer. Open
with the widest framing (what is this gym, who's it for, what's its overall
personality?), let each answer collapse the space, and ask the narrow questions
only once the broad ones have made them relevant. **Get precise at the END, not
the start.** The plan below is a guide, **not a script** — rebuild every
question's options from what the user has actually said. If you're about to offer
an option that only makes sense under an unconfirmed assumption, stop and ask the
broader question first.

**Same-theme options that aren't a real choice.** Every option in a question must
be a genuinely *distinct* alternative pointing a different direction, so the
user's pick tells you something. Five flavours of one idea teaches nothing (they
tick all of them) — offer real branches ("hardcore fight team" vs "welcoming and
social" vs "technical and studious" vs "competition-driven"), not synonyms.

### 6. Spread the queries broadly across the content spectrum

Word `videos.queries` to surface content spread **as broadly as possible across
the nine `VideoType` genres** (`schema/video_type.py`): `educational`,
`analysis`, `entertainment`, `news`, `interview`, `vlog`, `professional`,
`clips`, `memes`. Breadth lives in the *queries themselves* — reach across the
clusters: teach (educational/analysis), enjoy (entertainment/clips/memes), inform
(news), human (vlog/interview), and peak (professional). Don't let the gym's
"main thing" (e.g. technique for a how-to gym) crowd out the rest.
**`professional` means pros/elite competitors performing the craft at the top
level** (pro fight footage, championship play) — NOT corporate / high-production
video.

## The question plan — all about the gym (a guide, not a script)

Ordered **broadest → most specific** on purpose (principle 5). Re-derive each
question and its options from the answers so far; keep the **bold** ones.

- **Gym name** *(open text → informs `gym_id`)*. The first question and the only
  plain-text prompt. Derive a snake_case `gym_id` from it (confirm if ambiguous).
- **Discipline(s)** *(single- or multi-select → `gym_type`)*. What kind of gym is
  it (Muay Thai, BJJ, vinyasa, reformer pilates, CrossFit…)? Map the answer to
  `GymType` enum value(s); confirm the **primary** if several. Use it to pre-tune
  every later option bank.
- **Theme** *(single-select → `theme`)*. Which produced design does it run? Offer
  the plausible matches from `ThemeService/apps/combatden/` for that discipline;
  the user picks. Never guess silently.
- **Overall personality / vibe** *(single-select, the broad opener)*. What's this
  gym fundamentally like? Offer genuinely divergent branches — don't assume it
  from the discipline. Whatever they pick collapses the space below.
- **Target persona** *(single/multi-select)*. Who is it *for* — complete
  beginners, committed hobbyists, competitors, parents signing up kids, busy
  professionals? Shape options around the vibe just chosen.
- **What it teaches / believes** *(single/multi-select → its philosophy)*. What
  does the gym stand for and emphasize — its approach, values, the way it thinks
  the craft should be done? The heart of the brief; derive options from the vibe +
  persona.
- **What it rejects / doesn't believe** *(single/multi-select → its
  anti-philosophy)*. The sharp flip side — the approaches, framings, or bad habits
  *within the field* the gym pushes back on. Let the user answer in their **own
  natural language**; broad is expected ("McDojo stuff", "ego lifting"). You
  **should** ask a clarifying question about what they *mean* ("when you say
  McDojo, is it the belt-selling, the unrealistic technique, or the marketing?") —
  that's understanding their values, the whole point. What you must **never** do
  is ask them about **videos or titles**; turning their meaning into concrete,
  title-verifiable avoids is **your** job at the derive step.

## Derive the specification — `videos_desc` and `avoid_desc`

Once you understand the gym, build the spec with **no further video questions**.

1. **Derive `videos_desc`** from the discipline, persona, culture, and philosophy
   — tight, concrete prose describing the kinds of videos worth surfacing for
   *this* gym.
2. **Derive `avoid_desc`** — **your reasoning work, not the user's**. They handed
   you a natural-language want ("no McDojo stuff", "nothing that says BJJ is
   useless"); silently translate each into the concrete, title/description-
   verifiable form the scan can act on (it sees title + description + transcript).
   Every avoid must pass **two tests**:
   - **Specific** — a concrete thing, not a vibe. "fake masters", "McDojo
     content", "self-defense fantasy", "bad technique" are **too broad**: they
     name a feeling, not a video. Name the actual claim, phrasing, technique, or
     format.
   - **Verifiable from a title/description** — something a classifier could spot.
     "low-credibility instructors" isn't; *"titles promising one move guarantees a
     street-fight win / 'deadliest [technique]'"* is.

   Worked translations: "McDojo" → "videos selling fast-track belt promotions or
   guaranteed-rank programs"; "self-defense fantasy" → "titles claiming one move
   guarantees a street-fight win"; "BJJ is useless" → "'BJJ doesn't work in a real
   fight' debate/reaction videos". Also exclude **cross-discipline 'X vs Y / which
   is better'** framings — they advertise rival disciplines. **Never** add
   obviously-unrelated topics (a Muay Thai gym excluding "cooking videos" is
   pointless). Test each: *could I tell this matches from a title + description?*
   If not, rewrite it.
3. **Descriptions gate.** Show the composed `videos_desc` + `avoid_desc` back via
   one `AskUserQuestion` (approve / revise). This is the content approval; loop
   until approved.
4. **Draft the queries.** Concrete `query` strings — real phrases someone would
   type into YouTube, specific to this gym's world — **spread broadly across the
   content spectrum** (principle 6). Show them so the user can cut/add; don't make
   them write the set.

## Classes & rewards — derive + approve, then verify every image

`classes` and `rewards` live on the gym, so authoring them is a gym-maker job (the
old pipeline's "class images" phase). Only do this when the user wants cards now;
otherwise leave them `null`.

- **Derive + approve the cards' text.** From the discipline, propose on-brand
  class names + one-line descriptions (e.g. Muay Thai → Fundamentals, Clinch, Pad
  Work, Sparring), or reward names + `price_label` + `points_cost`. Show via
  `AskUserQuestion` for approval / edits.
- **Instructor data (classes only).** `ClassImage` needs `instructor_name` /
  `instructor_bio` / `instructor_image_url`. For a **real, named gym**, ask the
  user — never fabricate a real person's bio. For a **demo / archetype profile
  with no real gym behind it**, you may fabricate plausible names + bios (mark them
  as placeholders). Rewards have **no instructor**.
- **Find + VISUALLY verify EVERY image — no exceptions.** Applies to all class
  images, all instructor headshots, and all reward images. Never write an
  `image_url` you haven't downloaded and looked at. For each:
  1. **Source from Wikimedia Commons** (stable, hotlinkable, licensed — never
     random-placeholder services like picsum, which return unrelated photos):
     ```
     curl -s -A "CombatDen/1.0" "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=<query>&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url|size&iiurlwidth=1280&format=json"
     ```
     Use the `iiurlwidth` thumb for landscape class/reward images; prefer
     portrait results for headshots.
  2. **Download** to a temp file: `curl -s -A "CombatDen/1.0" "<url>" -o /tmp/cand.jpg`
     (a `<!DOCTYPE html>` body means a bad thumb size — use a size the API
     returned).
  3. **VIEW it** — `Read` `/tmp/cand.jpg` and actually look. Confirm: (i) class /
     reward images are **horizontal** (wider than tall); (ii) it truly **is the
     thing** — the activity for a class, a real coach portrait for a headshot;
     (iii) it's clean — no watermark, logo, heavy text, collage, AI-slop, or
     wrong subject.
  4. Failed any check → pick another candidate and repeat. Only a URL that passed
     (3) goes in the gym file.

> **Known limitation:** hotlinked internet images rot, can be hotlink-blocked,
> and carry licensing risk on a customer-facing screen. The durable answer is
> owned / hosted images (generated via ThemeService, or gym-uploaded). This is the
> interim brand-match step.

## Anti-patterns

- Never interview the user about videos, genres, search terms, or "content
  strategy" — ask only about the **gym** and derive the video output yourself.
- Never ask more than one question per turn; every gym question is
  multiple-choice except the first (the name).
- Never number questions to the user, and never think out loud.
- Never assume which kind of gym it is from its discipline — open broadest, narrow
  at the end (principle 5).
- Never offer a multi-select whose options are all one theme — every option a
  distinct branch.
- Never write **vague / abstract** avoids ("fake masters", "McDojo content", "bad
  technique") — every avoid must be **specific AND verifiable from a title /
  description**. Test each one.
- Never fill `avoid_desc` with obviously-unrelated topics.
- Never write any `image_url` (class, headshot, or reward) you haven't downloaded
  and **viewed**; never use random-placeholder image services.
- Never fabricate a real, named gym's instructor bios; only demo / archetype
  profiles may use placeholders.
- Never hand-edit the pipeline fields (`good_video_ids` / `rejected_video_ids` /
  `scan_costs`) — they're machine state.
- Never invent a `Gym` field — the model is `extra="forbid"`.
- Never skip `make gym-check`, and never use bare `python3` / `.venv/bin/*`.
