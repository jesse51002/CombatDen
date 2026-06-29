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
theme: VinyasaFlow            # the ThemeService design id this gym runs
videos:
  specification:
    # SHORT pair — a ≤2-sentence skim summary, for easy viewing. NOT scanned.
    # Plain prose; the folded `>-` scalar is fine here.
    short_videos_desc: >-
      Led, breath-paced vinyasa classes with clear instruction, PLUS the fun
      side — teacher vlogs, studio behind-the-scenes, and flow-with-music.
    short_avoid_desc: >-
      Off-topic, clickbait "yoga for weight loss" promises, gear hauls, and
      "yoga vs pilates" / "yoga is useless" debate videos.
    # LONG pair — the full, context-rich criteria the SCAN judges against (≥2
    # chars). A markdown DOCUMENT: use the LITERAL block scalar `|-` so the
    # newlines/headings/bullets survive (the folded `>-` collapses them into
    # one paragraph and destroys the markdown). The app renders this verbatim.
    videos_desc: |-                   # what the scan should KEEP (markdown)
      # What we surface

      Led full-length vinyasa classes, breath-paced and clear — and the
      enjoyable, human side of the practice.

      ## Classes & foundations
      - Led full-length vinyasa classes, breath-paced and clearly cued
      - Foundations: sun salutations, alignment, breath-to-movement tutorials

      ## The fun & human side
      - Teacher vlogs and "day in the life", studio/retreat behind-the-scenes
      - Relatable class humour, flow-with-music edits, and interviews
    avoid_desc: |-                    # what the scan should REJECT (markdown)
      # What we avoid

      Off-topic, genuinely low-quality, or clickbait videos.

      ## Reject
      - "Yoga for weight loss / flat abs" promises and gear-haul shilling
      - "Yoga vs pilates" / "yoga is useless" debate or reaction videos

      Don't reject a video just for being short, a vlog, a highlight, or fun —
      that content is wanted.
  queries:                            # the searches the scraper runs (mix genres!)
    - beginner vinyasa yoga foundations    # teach
    - sun salutation breakdown tutorial    # teach
    - day in the life of a yoga teacher    # human / vlog
    - what a vinyasa class is really like  # enjoy
    - yoga teacher reacts to yoga fails    # enjoy / entertainment
    - yoga retreat vlog                    # human / vlog
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
  `ThemeService/apps/combatden/`, e.g. `ApexMMA`, `VinyasaFlow`). The
  theme→gym link IS this field; the gym browser serves it and the app loads it.
  The theme also supplies the gym's card art (its celebration image), derived by
  the API — you do **not** store an image url on the gym.
- **`videos.specification`** — the scan's criteria, in **two tiers**:
  - **LONG** (`videos_desc` / `avoid_desc`) — the full, context-rich criteria,
    written as a **markdown document**. `videos_desc` = what to surface;
    `avoid_desc` = what to reject. Both ≥2 chars, both **required**, and the
    **only** pair the scan judges against. Write them concretely and richly —
    vague specs make the scan noisy, and there's no length limit (add as much
    context as the gym needs). **Markdown structure — titles are required:**
    every long description is a real document with hashtag headings. Start with
    a `#` document title (`# What we surface` / `# What we avoid`), a one-line
    framing sentence, then `##` section headings each with a `-` bullet list (a
    short closing line is fine). Use `#`/`##` for titles and sections — **not**
    bold (`**…**`) as a stand-in for headings; the renderer needs the heading
    hierarchy to format the document. **YAML:** these MUST use the **literal
    block scalar `|-`**,
    never the folded `>-` — `>-` collapses the newlines into one paragraph and
    destroys the markdown. The app renders this markdown verbatim in the agent
    view's prompt panel, so keep it clean and readable.
    **The feed is for enjoyment, not just instruction.** `videos_desc` must
    welcome the *fun and human* side of the gym's world too — entertainment,
    highlight/clip reels, creator vlogs and "day in the life", behind-the-scenes,
    funny moments, interviews, transformations — not only how-to/technique
    content. Correspondingly, `avoid_desc` must **never** reject a video just for
    being short, a vlog, a highlight, a clip, or entertaining; it drops only
    genuine low-value/off-topic content (clickbait, scams, misinformation,
    not-the-discipline, cross-discipline "X vs Y", anti-discipline rage-bait,
    unsafe stunts). See principle 6.
  - **SHORT** (`short_videos_desc` / `short_avoid_desc`) — a ~2-sentence summary
    of each, for **easy viewing** (skimming the file, the approval gate). The
    scan never reads these. **Plain prose, NOT markdown** (the folded `>-`
    scalar is fine). **Optional for now** (a gym may omit them); they become
    required once every gym has been backfilled. When present, ≥2 chars.
- **`videos.queries`** — the YouTube searches that populate this gym's slice of
  the shared pool. Author them to cover the gym's disciplines well **and across
  the content spectrum** — a healthy share must target the *enjoy* and *human*
  clusters (entertainment, clips, vlogs, interviews), not just *teach*
  (educational/how-to). An all-educational query set is wrong (principle 6). The
  scraper reads them. Empty list is allowed (a gym that rides on others'
  queries), but then nothing new is fetched for it.

  > **Note — this guide covers template YAML gyms only.** The `queries` field
  > above applies to the hand-authored `VideoService/gyms/<gym_id>.yaml` template
  > files (the 76 demo gym archetypes). For **real customer gyms** (UUID-keyed,
  > stored in `gym_video_spec` in Postgres), query generation is handled by the
  > FastApiBackend `videos` domain: `POST
  > /api/v1/gyms/{gym_id}/video-agent/generate-queries` (single structured LLM
  > call) and `POST /api/v1/gyms/{gym_id}/video-agent` (conversational agent). The
  > genre-spread methodology from this skill (principle 6) was ported into those
  > backend prompts.
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
   them and let the user cut/add. (Don't invent filler queries.) This step
   applies to template YAML gyms. For real customer gyms, queries are generated
   via `POST /api/v1/gyms/{gym_id}/video-agent/generate-queries` on the backend.
5. **Classes / rewards?** — only if the user wants them now; otherwise leave
   `null`. Get real titles/images/points from the user — don't fabricate.

## Write, then validate

1. Write `gyms/<gym_id>.yaml` with the surface above (empty pipeline fields).
2. **Validate** it round-trips against the `Gym` model before you're done — load
   the file through the Pydantic model:

   ```bash
   poetry run python -c "import yaml; from schema import Gym; \
     Gym(**yaml.safe_load(open('gyms/<gym_id>.yaml'))); print('ok')"
   ```

   A clean load means the schema, the `gym_id`/filename match, and the enum
   values are all valid (the model is `extra="forbid"`, so typos fail loudly).
   `make test` also round-trips every gym. Fix and re-run until clean. **Always
   `poetry run`**, never bare `python3` or `.venv/bin/*`.

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

### 6. A feed is for enjoyment — spread queries across the whole spectrum

The in-app feed is something members **enjoy scrolling**, not a how-to course
catalogue. So `videos.queries` must surface content spread **as broadly as
possible across the nine `VideoType` genres** (`schema/video_type.py`):
`educational`, `analysis`, `entertainment`, `news`, `interview`, `vlog`,
`professional`, `clips`, `memes`. Breadth lives in the *queries themselves* —
reach across the clusters: teach (educational/analysis), **enjoy
(entertainment/clips/memes)**, inform (news), **human (vlog/interview)**, and
peak (professional).

**The most common failure is an all-educational query set — do not do this.**
Fun, entertaining, vlog, clip, highlight, interview and "day in the life" content
is *explicitly wanted* in every gym's feed. As a rule of thumb a healthy set is
**only about half teach/how-to**; the rest should be enjoy + human + peak.
Calibrate the *flavour* of fun to the gym's culture (a calm wellness studio's fun
is teacher vlogs, studio behind-the-scenes and aesthetic edits; a competitive or
playful gym's fun is highlight reels, funny moments, challenges and montages) —
but **never drop the fun to zero**, and never let the gym's "main thing"
(e.g. technique for a how-to gym) crowd out the rest.

This cuts both ways: `videos_desc` should *welcome* that fun/human content, and
`avoid_desc` must **never reject a video merely for being short, a vlog, a clip,
a highlight, or entertaining** — only for being genuinely low-value (clickbait,
scams, misinformation, off-topic, cross-discipline "X vs Y", anti-discipline
rage-bait, unsafe stunts).

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

## Derive the specification — the LONG pair (scan) + SHORT pair (viewing)

Once you understand the gym, build the spec with **no further video questions**.
You compose **two tiers**: the long `videos_desc` / `avoid_desc` the scan judges
against, then a short `short_videos_desc` / `short_avoid_desc` summary for easy
viewing. Derive the long pair first (steps 1–2), then condense it (step 3). The
**long pair is a markdown document** (one-line framing, then `**Bold**`
sub-labels with `-` bullets), written into YAML with a **literal `|-` block
scalar** so the formatting survives; the **short pair stays plain prose**.

1. **Derive `videos_desc`** (LONG) from the discipline, persona, culture, and
   philosophy — a concrete **markdown document** describing the kinds of videos
   worth surfacing for *this* gym: a `# What we surface` title, a framing line,
   then `##` section headings (e.g. `## Technique & classes`, `## The fun &
   human side`) each with `-` bullets. Be **rich and
   specific**, not terse — this is the scan's full context, and there's no
   length limit. Cover **both halves of the feed**: the
   instructional/how-to/technique/class content *and* the fun, human content
   members enjoy — entertainment, highlight/clip reels, creator vlogs and "day in
   the life", behind-the-scenes, funny moments, interviews, transformations.
   Calibrate the flavour to the gym's culture, but never describe a how-to-only
   feed (principle 6).
2. **Derive `avoid_desc`** (LONG) — **your reasoning work, not the user's**, and
   likewise a **markdown document** (a `# What we avoid` title, a framing line,
   a `## Reject` bullet list, and a closing reminder that fun/short/vlog content
   is NOT a reason to reject). They handed
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

   **Never reject content by format.** An avoid drops *low-value* content, not
   *fun* content. Do NOT write avoids like "short clips", "social clips", "vlogs",
   "highlights", "non-instructional", or "anything that isn't a followable class"
   — that content is wanted (principle 6). Reject only the genuinely bad: off-topic,
   clickbait, scams/misinformation, cross-discipline "X vs Y", anti-discipline
   rage-bait, and unsafe stunts. If an avoid would catch a perfectly good gym vlog
   or highlight reel, it's wrong — delete it.
3. **Condense to the SHORT pair.** Distill each long description into a
   ~2-sentence `short_videos_desc` / `short_avoid_desc` — the same intent, fast
   to skim. These are display-only (the scan never reads them); their job is to
   make the gym readable at a glance. Don't drop the key specifics, just trim.
4. **Descriptions gate.** Show **both tiers** — the long `videos_desc` /
   `avoid_desc` and the short `short_videos_desc` / `short_avoid_desc` — back via
   one `AskUserQuestion` (approve / revise). This is the content approval; loop
   until approved.
5. **Draft the queries.** Concrete `query` strings — real phrases someone would
   type into YouTube, specific to this gym's world — **spread broadly across the
   content spectrum** (principle 6). About half teach/how-to; the rest must hit
   the *enjoy* and *human* clusters (entertainment, clips, highlights, vlogs,
   "day in the life", interviews, transformations), flavoured to the gym's
   culture. A query set that's all educational is wrong. Show them so the user can
   cut/add; don't make them write the set.

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
  1. **Source activity / people / class imagery from Pexels** — clean, modern,
     commercial-grade stock that hotlinks and reads as a real studio/gym.
     **Do NOT use Wikimedia Commons for activity or people shots:** it is
     public-domain-dominated, so "boxing class", "yoga", "spin", etc. come back
     mostly US-military and competition/Olympic photos — off-brand and
     trust-destroying on a member screen. (Commons is fine only for a plain
     product/object shot — a dumbbell, a gi, a water bottle — where military
     bleed isn't a risk. Never use random-placeholder services like picsum.)
     Find candidates with WebSearch restricted to Pexels, then build the direct
     CDN url from the photo id in the result URL (no API key needed):
     ```
     WebSearch({ query: "<discipline> class", allowed_domains: ["pexels.com"] })
     # result page https://www.pexels.com/photo/<slug>-<ID>/  → take trailing <ID>
     # direct hotlinkable CDN url (this exact pattern works):
     https://images.pexels.com/photos/<ID>/pexels-photo-<ID>.jpeg?auto=compress&cs=tinysrgb&w=1200
     ```
     Skip `/video/` and `/search/` results.
  2. **Download** with a browser User-Agent to a temp file:
     `curl -s -A "Mozilla/5.0 … Chrome/120" "<cdn-url>" -o /tmp/cand.jpg`
     (a `<!DOCTYPE html>` body means a bad id/url — pick another).
  3. **VIEW it** — `Read` `/tmp/cand.jpg` and actually look. Confirm: (i) class /
     reward images are **horizontal** (wider than tall); (ii) it truly **is the
     thing** — the activity for a class, a real coach portrait for a headshot;
     (iii) it's clean — no watermark, logo, heavy text, collage, AI-slop,
     **military uniforms/fatigues, competition bibs/medals**, or wrong subject.
  4. Failed any check → pick another candidate and repeat. Only a URL that passed
     (3) goes in the gym file.
  - **At scale (many gyms): group by discipline.** Verify one small image set per
    discipline cluster and reuse it across that cluster's gyms (e.g. a Sonnet
    workflow fanned out one agent per cluster), rather than sourcing per-gym. Do
    the visual vetting with **Sonnet or stronger — Haiku is too weak for it** (it
    has waved through 18th-century paintings and recognizable celebrities as
    "instructor headshots").

> **Known limitation:** hotlinked internet images rot and can be hotlink-blocked.
> The durable answer is owned / hosted images (generated via ThemeService, or
> gym-uploaded). Pexels-via-CDN is the interim brand-match step.

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
- Never write an **all-educational / how-to-only** feed. The feed is for
  enjoyment too — `videos_desc` and the queries must include fun + human content
  (entertainment, clips, highlights, vlogs, "day in the life", interviews),
  flavoured to the gym's culture (principle 6).
- Never reject content **by format**: no avoids for "short clips", "vlogs",
  "highlights", "social clips", "non-instructional", or "anything that isn't a
  followable class" — that content is wanted. Avoids drop only genuinely
  low-value content (clickbait, scams, off-topic, "X vs Y", anti-discipline
  rage-bait, unsafe stunts).
- Never write the **LONG** descriptions with a folded `>-` scalar — they're
  markdown documents and `>-` flattens the newlines/headings/bullets. Use the
  literal `|-` block scalar. (The **SHORT** pair stays plain prose; `>-` is fine
  there.)
- Never write a long description without **hashtag headings** — every long doc
  needs a `#` title and `##` section headings (not bold `**…**` as fake
  headings). A markdown document without titles doesn't format properly.
- Never write any `image_url` (class, headshot, or reward) you haven't downloaded
  and **viewed**; never use random-placeholder image services; never source
  activity / people imagery from Wikimedia Commons (military & competition bleed)
  — use Pexels for those (see the image step above).
- Never fabricate a real, named gym's instructor bios; only demo / archetype
  profiles may use placeholders.
- Never hand-edit the pipeline fields (`good_video_ids` / `rejected_video_ids` /
  `scan_costs`) — they're machine state.
- Never invent a `Gym` field — the model is `extra="forbid"`.
- Never skip the round-trip validation (load through the `Gym` model / `make
  test`), and never use bare `python3` / `.venv/bin/*`.
