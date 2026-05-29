# Option banks for the brand-brief interview

Researched menus the interview offers. **Every item is a recommendation, not a
default.** Present 2–4 at a time, tied to the user's earlier answers; the user
picks, edits, or rejects. Never select one for them. The schema lives
authoritatively in `schema/customization.py` — it is not duplicated here.

---

## Company archetypes (Q2)

Each archetype carries an example *essence* phrasing (for Q3 scaffolding) and a
visual-system starter set (for Q7). Offer the essence as a take-it-or-edit-it
line, never as the answer.

### Energetic / hype
Performance, intensity, push-yourself (combat sports, HIIT, lifting, bootcamp).
- Essence shape: *"Train hard, no excuses — a [discipline] app that pushes you to show up and leave it all on the mat."*
- Feel: bold, kinetic, high-contrast, confident.
- Medium & materials: forged metal, chalk, sweat-matte rubber, taped knuckles.
- Finish & light: hard directional light, deep shadow, punchy.
- Energy by role: heroes explode; persistent UI stays disciplined and quiet.
- Hard nos: nothing cute, pastel, soft, or corporate-clean.

### Calm / restorative
Wellbeing, low-pressure, recovery (yoga, mobility, gentle cycling, breathwork).
- Essence shape: *"Take it easy — a [discipline] studio app that rides for wellbeing, not for the burn."*
- Feel: soft, airy, serene, unhurried.
- Medium & materials: soft matte surfaces, rounded organic geometry, linen, clay.
- Finish & light: diffuse ambient light, gentle long shadows.
- Energy by role: even the celebratory moments are warm, never loud.
- Hard nos: no neon, no high contrast, no speed lines, no sweat-and-grind.

### Playful / joyful
Fun-first, delight over polish, mascot-forward (dance, kids, social fitness).
- Essence shape: *"[Verb] it out — a light, fun, bubbly [discipline] app where [mascot] cheers you on."*
- Feel: light, fun, bubbly, welcoming.
- Medium & materials: squishy matte plastic, balloon-like inflated forms, candy, felt.
- Finish & light: bright even light, soft rounded shadow, no grit.
- Energy by role: heroes bounce and celebrate; tiny icons stay friendly but calm.
- Hard nos: nothing gritty, dark, heavy, or battle-worn; no muted palettes.

### Premium / refined
Boutique, understated luxury, restraint (high-end studio, coaching, members club).
- Essence shape: *"A members' [discipline] app that earns attention by restraint, not noise."*
- Feel: refined, quiet, deliberate, confident.
- Medium & materials: brushed metal, stone, matte glass, fine grain.
- Finish & light: low-key controlled light, subtle gradients.
- Energy by role: heroes are composed, not flashy; UI is precise and sparse.
- Hard nos: no clutter, no loud gradients, no gamified confetti energy.

### Community / grassroots
Local club, belonging, no-frills warmth (community gym, rec league, dojo).
- Essence shape: *"The neighbourhood [discipline] club app — show up, belong, get better together."*
- Feel: warm, honest, approachable, lived-in.
- Medium & materials: worn wood, canvas, enamel pin, hand-painted signage.
- Finish & light: natural daylight, friendly soft shadow.
- Energy by role: heroes feel handmade and warm; UI stays plain and legible.
- Hard nos: no corporate gloss, no cold minimalism, no aspirational stock-photo sheen.

> Blends are normal (e.g. *playful + community*). When the user blends, ask
> which one leads, then borrow the secondary's hard-nos.

---

## Voice axis (Q5, structured assist)

Offer as a quick pick, then always follow with the open "in your own words" and
"must never sound like" prompts.

- Warm-encouraging — "you've got this," supportive, never saccharine.
- Calm-unhurried — steady, spacious, never barking or counting down.
- Bold-confident — direct, declarative, never hype-y sales.
- Playful-bubbly — light, funny, never childish or random.
- Understated-premium — spare, assured, never aloof.

---

## Colour mood ↔ hue-family pairings (C2/C3) with mode lean

Describe **families and intent**, never values. Mode lean is a recommendation
for C1, not a decision.

| Mood | Primary hue family | Accent direction | Typical mode lean |
|---|---|---|---|
| Energetic / hot | reds, oranges, ember | a sharp cool pop (electric blue, lime) | dark |
| Disciplined / serious | deep red, oxblood, steel | restrained gold or steel-blue | dark |
| Calm / natural | sage, eucalyptus, sea-glass | dusty clay / warm terracotta | light |
| Joyful / sunny | warm yellow, coral, sky | a clearly different cheerful hue (bubblegum, sky) | light |
| Premium / quiet | desaturated jewel tone, ink | a single metallic or muted brass | dark or light |
| Grassroots / warm | clay, olive, brick | hand-painted enamel blue or red | light |

Guidance to pass through to the user:
- One confident accent beats three competing ones; the accent must read as a
  visibly different hue from the primary.
- Background and text are near-neutral with a faint tint toward the brand hue —
  they are *character* ("warm oat", "cool slate"), never bright.
- Saturation intent matters more than the exact hue: say "gently desaturated,
  natural" or "vivid and confident" — the pipeline resolves the rest.

---

## Mode decision helper (C1)

If the user is unsure, offer this framing (then still require an explicit pick):

- **Dark** — focus, intensity, evening/gym ambience, content-forward; common
  for performance and premium brands.
- **Light** — open, friendly, daytime, approachable; common for calm,
  playful, and community brands.
- Mode is an enum that silently inverts the whole palette — never infer it
  from the archetype alone; confirm.
