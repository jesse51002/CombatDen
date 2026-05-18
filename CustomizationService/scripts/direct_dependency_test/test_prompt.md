You write ONE production-quality image-generation prompt for the single
subject described below. The `prompt` is read by an image model — it must
describe the artwork and nothing else.

Return:

- `prompt`: the exact text the image model receives. Just the prompt — no
  preamble, no quotes, no markdown, no labels.
- `dependency_usage`: a list with one entry per related asset listed below
  (under "Related assets"). Return an EMPTY list when no related assets
  are listed. The rules for filling it are in that section when present.

The subject description tells you WHAT to depict and its style intent. It may
also mention where or how the asset is used in the app — a screen name, a
flow, a moment. That context is for your understanding only: NEVER copy
placement, screen names, app flow, or usage wording into the `prompt`. The
prompt is the art piece, not the app around it.

Read the asset's emotional register from the subject and how it is used,
and match the prompt's energy to it:

- A celebration, reward, win, milestone, or unlock should feel loud,
  energetic, and fun — be creative and artistic here: richer composition,
  more visual life, less simple. This is where expressiveness earns its
  keep; lean toward Dynamic hero.
- A persistent, utility, status, or navigational element — an icon, a
  marker, a small recurring graphic — should feel clean and calm. It can
  still be finely crafted and detailed, but quiet and restrained, never
  loud; lean toward Clean icon or Calm float.
- Anything between the two sits between the two — let the moment set the
  volume.

This register is inferred from the context only; like all such context it
never appears in the `prompt` as words such as "celebration" or "icon".

Choose the treatment that best fits the subject. These are structures, not a
fixed look — keep the structure, derive the mood, colour, and material from
the brand brief and palette below. Each example is a *different* brand on
purpose: copy the shape, never the vibe. Every example obeys every rule
further down.

- **Clean icon** — a single object, front-facing, centred, minimal; reads at
  a glance.
  - Brand: a serene meditation app, dark mode. Subject: the daily-streak
    flame.
  - `prompt`: A smooth rounded flame glyph, single object front-facing and
    centred, soft matte finish, even light with a faint cool rim on its own
    edge, calm slate-blue and pale-lilac palette, flat solid pure-black
    background, minimal app-icon style

- **Dynamic hero** — a few related objects in a balanced floating
  composition, energetic; optionally an explosive-but-controlled burst from
  the centre.
  - Brand: a playful kids' language app, light mode. Subject: the
    lesson-complete celebration.
  - `prompt`: A friendly cartoon owl with three picture-book tiles and a
    looping ribbon, balanced floating composition with a light burst outward
    from the centre, soft toy-like materials, even studio light shading each
    object's own surface, cheerful coral and sky-blue palette, flat solid
    pure-white background, rounded 3D illustration style

- **Calm float** — one or a few objects suspended and balanced, no burst,
  quiet.
  - Brand: a warm personal-finance app, light mode. Subject: the
    savings-goal reached.
  - `prompt`: A glossy ceramic piggy bank with one gold coin balanced in its
    slot, single subject suspended and quietly balanced, soft even studio
    light, gentle warm highlights on its own curved surface, muted sage and
    warm-gold palette, flat solid pure-white background, clean modern 3D
    product style

- **Achievement** — a badge, medal, belt, or crest; straight-on, centred,
  symmetrical.
  - Brand: a sleek developer tool, dark mode. Subject: the top-contributor
    badge.
  - `prompt`: A hexagonal metal badge with an embossed laurel and one inset
    gem, straight-on, centred, perfectly symmetrical, brushed-steel and
    deep-emerald materials, crisp studio light shading the badge's own
    facets, flat solid pure-black background, premium emblem style

- **Stylized environment-object** — a place (an arena, a room, a field)
  rendered as one self-contained floating object, never a photographed
  location.
  - Brand: a warm travel-booking app, light mode. Subject: the trip-booked
    confirmation.
  - `prompt`: A tiny stylized seaside town as one self-contained floating
    island, pastel houses and a lighthouse and a curl of road, not a
    photographed place, soft even light shading the island's own forms,
    warm terracotta and sea-glass palette, flat solid pure-white
    background, clean miniature 3D diorama style

- **Studio product** — photoreal materials and studio lighting on the
  subject itself; a product shot with no real-world setting.
  - Brand: a refined specialty-coffee subscription, dark mode. Subject: the
    new single-origin bag.
  - `prompt`: A matte kraft coffee bag with a foil seal and a single roasted
    bean resting against it, photoreal materials and crisp studio lighting
    on the subject itself with no setting, fine grain and foil sheen on
    their own surfaces, deep-espresso and cream palette, flat solid
    pure-black background, premium product-shot realism

Composing your own treatment is allowed and encouraged when nothing above is
a close match. The six are the well-trodden paths, not a fence: prefer a
listed treatment whenever one genuinely fits — for now, predictability and
consistency across an app's assets matter more than novelty. But if the
subject has no close match, feel completely free to compose a new treatment
that serves it and the brand. Be expressive within the rules: the rules
below fix the format and the clean cutout, not the imagination — a new
treatment must still obey every one of them.

The background is fixed and not yours to choose: the subject sits on a
single flat, perfectly even, solid background that is exactly
pure black (the app is in dark mode). Nothing else is in frame — no scene, no real-world
setting, no props, no shadow cast onto a ground or surface, no gradient, no
texture, no border. This holds for every treatment, including the studio
product look: photoreal materials and lighting are welcome, an in-context
setting is not.

Craft rules (how good assets avoid amateur output):

- Match the app's design direction. The brand brief below *is* that
  direction — the shared look every asset in the app must wear. Treat it as
  a binding visual brief, not background: the medium, materials, and finish
  you choose must be the ones it implies, so this asset looks made by the
  same hand as the rest of the app. If the brief is sparse, commit to one
  plain coherent reading and reuse it — never a one-off flourish.
- Prefer objects. People and animals from image models drift into the
  uncanny and rarely cut out cleanly — default to objects, symbols, and
  gear. If a person or animal genuinely is the subject, it MUST be
  explicitly and unambiguously a simplified, stylized illustration (say
  so plainly — e.g. a flat minimal mascot, a simple stylized silhouette)
  — never photoreal or realistically detailed.
- Order the prompt Subject → Details → Style/Aesthetic, comma-separated.
- Give 4–6 high-signal details only — materials, composition, lighting,
  colour, style. Every clause must change what is drawn; if a clause does
  not change the picture, delete it. Image models degrade when
  over-described.
- Shadow and shading sit ON the subject's own surfaces, for depth and form
  — never "underneath" the subject or cast onto a surface. A cast shadow
  invents a ground plane and ruins the clean composite.
- Keep objects distinct. Never "intertwined", "merged", "fused", or similar
  — overlap reads as a single malformed blob.
- Pull the subject's own colours from the palette; let the brand brief set
  the mood. Restraint wins: one confident accent beats three competing
  ones. Do not give the subject the background colour.
- Stay tight: a few comma-separated clauses or two or three short
  sentences, roughly 30–60 words and never past ~75. No negative prompts,
  no parameters, no aspect-ratio or resolution syntax; at most one light
  quality cue, usually none.

--- Brand brief ---
Brand name: CombatDen
In short: Train like a pro — a premium combat-sports training and progression app for competitive fighters and serious amateurs.
In depth: CombatDen is a premium combat-sports training and progression app for
competitive fighters and serious amateurs across boxing, MMA, Muay
Thai, BJJ and wrestling. The audience is disciplined and unsentimental:
they want a tool that respects the work, not a gamified toy. The voice
is confident, terse and earned — a coach in your corner, never hype.

Visual system — the shared look every generated asset must wear:

- Feel: gritty but high-end. Forged, hard-earned, championship
  gravitas. Restraint over spectacle — quietly expensive, never flashy.
- Medium & materials: realistic sculpted 3D — forged and brushed
  metal, worn full-grain leather, taut canvas, dense matte rubber.
  Tangible, weighty, faintly battle-worn. Never cartoon, never flat
  vector, never glossy plastic.
- Finish & light: matte surfaces with a tight, controlled specular.
  Low-key studio lighting, one hard key with soft fill, deep shadow
  worked into each object's own surfaces for form and depth — no
  scene, no shadow cast onto a floor.
- Energy by role: rewards, wins, rank-ups and celebrations land with
  weight and forward momentum — impact, not confetti; powerful but
  still disciplined. Persistent UI icons and indicators are stripped,
  solid and calm — crafted but quiet, never loud.
- Hard nos: no neon, no glow, no rainbow or playful gradients, no
  sci-fi, no sparkles, no busy clutter, nothing cute.

--- Palette ---
  primary: oklch(35% 0.18 15) — Oxblood Red: Deep, saturated red with the weight of dried blood—a dark, serious primary that commands attention without shouting. Used sparingly for primary CTAs, rank-ups, and the moments that truly matter in training.
  background: oklch(18% 0.008 20) — Charcoal Black: Near-black warm charcoal with a whisper of red undertone and minimal chroma—reads as black but feels intentional and crafted, never dead or purely synthetic. The foundational canvas for the entire app.
  text: oklch(92% 0.01 45) — Bone White: A slightly muted, warm ivory that sits comfortably above WCAG AA contrast against the charcoal background. Calm and readable for headings and body copy, with enough warmth to feel premium rather than clinical.
  accent: oklch(58% 0.12 70) — Antique Gold: A desaturated, warm muted gold—aged trophy metal, not shiny or bright. Reserved for badges, rank highlights, and active states (nav items, tabs, timeframe pills), where it lands with earned dignity and never competes with the red.
--- Background (fixed by app theme) ---
pure black (the app is in dark mode)
--- Subject ---
A preview of the NEXT rank's belt — the tier the user is working toward, deliberately distinct from rank_belt (their current tier). Lives in the Profile screen's "Next Rank" section, inset inside a ~100x100 circular progress badge: an animated progress arc rings the badge and the image sits within it with ~22px padding, above a "Next Rank" title and an "X / Y classes to next tier" progress label. The moment is calm, between-classes browsing — motivational, not celebratory. It must read clearly inside a small circular badge without fighting the progress ring, and should clearly feel like a higher, aspirational belt tier the user has not reached yet.
--- Related assets (visual continuity) ---
The assets below were already generated for THIS SAME app. This image
should look like it came from the same hand — match their medium,
materials, finish and palette discipline so the set is coherent. Do NOT
copy their subject, composition or wording; this is its own distinct
subject.

For EACH related asset you ALSO decide how it should inform this image
and return that decision in the `dependency_usage` list — exactly one
entry per asset, `dependency` set to the asset's id EXACTLY as listed,
`usage` either `reference` or `direct`:

- Pick `reference` when this image only needs to *match the style,
  material, finish, palette, or family* of that asset — it is a
  sibling/companion asset that should look like it came from the same
  hand, but is its own distinct subject. The asset's description below is
  enough to steer the prompt; the asset image itself does not need to
  appear. Fold its look into the `prompt` text.

- Pick `direct` when this image must actually *contain* that asset, or
  something so close to it that re-generating from words alone would not
  be faithful enough — e.g. the same object shown again, a tighter/looser
  crop of it, the same emblem placed onto something, or a variation that
  must preserve that exact specific artwork. The asset image itself is
  fed to the generator, so do NOT describe that asset in `prompt`;
  instead write `prompt` as the instruction for how the result is built
  from / around it.

When unsure, prefer `reference`: it is the cheaper, lower-risk default
and covers the common "keep these assets visually consistent" case.
Reserve `direct` for a genuine "this specific image must be in/under the
result".

Related assets (use these ids exactly in `dependency_usage`):
  rank_belt: A championship belt coiled into a centred medallion, thick worn full-grain leather strap wrapping a forged antique-gold central plate embossed with a stern crest, straight-on and perfectly symmetrical, low-key studio key light raking across its own brushed metal and matte leather, oxblood-red inlay accent, flat solid pure-black background, premium sculpted 3D emblem style

