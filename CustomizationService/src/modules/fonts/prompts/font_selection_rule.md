You are choosing the typography for a real, shipped consumer app the
way a senior brand designer does — opinionated, restrained, and
specific. The app's brand and visual system are described below. You
are picking a Google Fonts family for each font slot the app declares.

This is one batched decision. You will see every slot at once and must
pick fonts that work TOGETHER, not three independently-good choices
that fight each other on screen.

For EACH slot you are given an id and a human description. Decide each
slot's TYPOGRAPHIC ROLE from its description alone (never from its id):

- If the description indicates a HEADLINE / HERO / CELEBRATION /
  large-size role (24px and up, short bursts, screen titles, count-up
  numerals): this is the **display lane**. The font can have personality
  and feel distinctive at a glance, but every character is a character
  that will be set large — picky proportions and quirks are amplified,
  so the family must be drawn for display use (Google Fonts category
  is usually `display`, sometimes a serif or sans built for headlines).
- If the description indicates BODY / UI TEXT / LABELS / LIST ROWS /
  long reading at 13–18px: this is the **body lane**. The family
  must be optimised for small-size legibility: generous x-height,
  open counters, a wide weight range (Regular through SemiBold or
  Bold minimum), and a quiet, neutral personality so it doesn't fight
  the brand. Display faces almost always fail this. Pick from `sans-serif`,
  `serif` (only if the brand reads editorial), or a humanist family
  that explicitly supports running text.
- If the description indicates NUMERIC / TABULAR / MONOSPACE: pick a
  family with tabular figures or a `monospace` family with even rhythm.

Pair the slots COHERENTLY. A two-font system fails when the two fonts
fight each other or look interchangeable. Strong pairings come from:

- **Category contrast**: a confident `serif` or `display` family for
  the headline lane against a humanist or grotesque sans for body —
  the eye reads the difference instantly.
- **Superfamily**: one family used at strongly contrasting weights /
  widths (Inter Display + Inter, IBM Plex Sans + IBM Plex Mono,
  Source Sans + Source Serif). Cohesive without being samey.
- **Mood**: both families share an underlying mood (warmth, edge,
  formality) but inhabit different roles.

Single-font systems are valid only when one slot exists or when every
slot honestly wants the same family. Pick a family with a generous
weight ladder (Regular / Medium / SemiBold / Bold at minimum) so
hierarchy is achievable through weight alone.

Match the BRAND VOICE described below. Read the long description
carefully and pick families that feel like a designer who knew the
brand would have picked them:

- **Playful / cute / bubbly** brands → rounded humanist sans with soft
  terminals (think: friendly geometric sans built for warmth, not
  Comic Sans).
- **Editorial / serious / refined** brands → high-contrast serif or
  modern grotesque used with restraint.
- **Athletic / energetic / kinetic** brands → confident grotesque or
  modern sans with a strong weight ladder. **NOT** the obvious
  condensed-all-caps reflex (see anti-clichés below).
- **Technical / data-dense / tooling** brands → grotesque sans with
  tabular figures, or a high-quality mono paired with a clean body
  sans.
- **Premium / luxury / craft** brands → a serif drawn with character
  for display, paired with a quiet sans that gets out of the way.

REFUSE the training-data clichés. These are the fonts a thoughtless
LLM picks because they're statistically associated with a category in
training data, not because they're right. Treat each as a **fail
condition** — if you are about to pick one of these, you have not
diagnosed the brand carefully enough; re-pick.

- **Bebas Neue, Oswald, Anton, Archivo Narrow** — the
  "fitness / athletic condensed all-caps" reflex. Every gym brand
  reaches for these; that's exactly why a thoughtful gym brand doesn't.
- **Pacifico, Lobster, Great Vibes, Sacramento, Dancing Script** —
  the "playful = script font" reflex. Scripts rarely set well in real
  product UI; they almost always look amateur.
- **Roboto, Open Sans, Lato, Nunito Sans** — the "any app, doesn't
  matter" defaults. They're fine, but they say "we didn't choose a
  font". If your pick is one of these you have skipped the choice.
- **Inter** for every tech / SaaS / startup brand — the second-order
  reflex once a designer has learned to avoid Roboto. Inter is a
  great font; reflexively picking it for tech anyway is still a
  reflex.
- **Montserrat** — the "real estate / agency / wedding invite" reflex.
  Overused to the point of category capture.
- **Playfair Display** — the "luxury blog / boutique e-commerce"
  reflex. Same problem.
- **Comic Sans / Comic Neue** — never. Not even ironically.

**Category-reflex check.** Run it twice:

1. *First-order*: if a designer could guess your pick from the brand
   category alone — fitness → Bebas, finance → Inter, kids' brand →
   Pacifico — you've hit the first reflex. Re-pick.
2. *Second-order*: if a designer could guess your pick from
   "category + the obvious anti-cliché" — fitness-that's-not-Bebas →
   Oswald; tech-that's-not-Roboto → Inter — you've hit the second
   reflex. Re-pick.

PRODUCTION-QUALITY BAR. Pick families a shipped consumer app would
actually use, not interesting Google Fonts experiments:

- The family must be well-drawn, mature, and broadly supported on
  Google Fonts.
- Body-lane slots must have at least Regular (400) AND a heavier
  weight (600 or 700) available — hierarchy needs the contrast.
- Variable fonts are a plus when present.
- Latin coverage is the minimum. If the brand brief mentions
  international users or specific non-Latin scripts, pick a family
  that supports them.
- Use the EXACT canonical Google Fonts family name with the right
  capitalisation (e.g. "Inter", "IBM Plex Sans", "DM Serif Display",
  "Bricolage Grotesque", "Funnel Display"). The validation step
  checks the live Google Fonts catalog; a typo or non-Google font
  fails and you'll be re-asked.

OUTPUT. For EACH slot return an object with three fields:

- `family`: the Google Fonts canonical family name, spelled exactly as
  Google lists it. No `var()`, no fallback chain, no CSS — just the
  family name.
- `display_name`: a short evocative human label for your choice (for
  example "Editorial Grotesk", "Plump Geometric", "Premium Slab") —
  a name, not a sentence. Different from `family`: `family` is what
  Google calls it, `display_name` is what YOU call it in the brand's
  voice.
- `description`: one or two sentences naming the role you've assigned
  this slot, the personality of the family, and what makes it the
  right pick for THIS brand specifically. No marketing copy, no hype.
  If you considered and rejected an obvious cliché, you may name it
  here ("an athletic display face that isn't the obvious condensed
  Bebas Neue reflex") — that's record-keeping, not bragging.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long

--- Already-chosen fonts (FIXED: do NOT return these; make your picks sit in harmony with them) ---
$fixed_context

--- Font slots to fill (return an object for ONLY these; honor any "user note" as a direct instruction for that slot) ---
$slots
