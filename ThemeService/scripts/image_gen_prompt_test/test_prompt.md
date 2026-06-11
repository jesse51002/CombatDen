  You write ONE production-quality image-generation prompt for the single
  subject described below. The `prompt` is read by an image model — it must
  describe the artwork and nothing else.

  Return one field:

  - `prompt`: the exact text the image model receives. Just the prompt — no
    preamble, no quotes, no markdown, no labels.

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
  Brand name: Modern Hot
  In short: Hot room, loud music, hard flow — a modern hot-yoga studio where the heat, the playlist and the sweat are part of the workout.
  In depth: Modern Hot is a modern hot-yoga studio and companion app for
  people who want their yoga to feel like a workout — a hot room, a
  curated playlist, and a flow that leaves the mat wet. The audience
  runs from athletic newcomers chasing the sweat to regulars who
  treat hot-class three nights a week like training. The brand sits
  in a deliberate spot: it is athletic, contemporary and high-energy
  — the studio that programs sculpt-flow alongside hot-power and
  means it — but it is NOT a ritualised, dialogue-driven 26-and-2
  Bikram room, and it is equally NOT a soft, candlelit restorative
  studio. The point is heat, music and a real sweat earned in
  eighty minutes.

  The voice is energetic and direct — a teacher with a wireless
  mic who cues over the playlist: "One more round, ride the beat —
  you've got this." Confident, athletic and warm under the energy,
  it credits the work without slipping into bro-hype. It must never
  sound like screaming bootcamp ("BEAST MODE"), saccharine wellness,
  a ritualised Bikram dialogue script, or sterile corporate copy.

  Modern Hot has no mascot. Its anchor is a heat-and-soundwave motif
  — a rising heat curl threaded with a clean audio waveform —
  standing for the hot room and the music that drives it — carried
  into the brand mark and echoed through its object iconography. A
  sweat-beaded steel water bottle, a damp dark mat-towel and a
  headphone silhouette complete the recurring object notes.
  Celebratory moments bring the personality through dim,
  spot-lit, sweat-shining compositions, never a character; small,
  persistent elements stay clean, abstract and razor-legible at
  small size. The brand mark stays a clean, professional mark a
  real modern hot studio would use, never a busy illustrated scene.

  Visual system — the shared look every generated asset must wear:

  - Feel: athletic, contemporary and high-energy — the dim hot room
    five seconds before the first beat drops. Charged and modern,
    coiled rather than chaotic, never devotional and never soft.
  - Medium & materials: glossy stylised 3D in sweat-beaded brushed
    steel, dark damp mat-rubber, neoprene grip, smoked glass and
    the faint heat-haze of a hot studio. Tactile and engineered,
    with the heat-and-wave motif living in the composition. Never
    pastel, never clip-art, never devotional-ornamental.
  - Finish & light: hot directional spotlights cutting through
    heat-haze, deep falloff into the dim room, a single
    saturated colour wash on the back wall. Dramatic studio-floor
    staging, never moody-grim and never flat.
  - Energy by role: celebratory moments hit big and athletic — a
    hot pop of brand colour over the sweat-shine, the playlist
    crest, never confetti chaos. Small, persistent elements stay
    clean, sharp and quiet, reading instantly at small size.
  - Hard nos: no devotional ornament, mandala or Sanskrit-as-style
    used as a brand surface; no chanted-shala signals; no
    candle-and-blanket restorative softness; no cute, cartoon,
    pastel or bubbly; no mascot, character, creature or face of
    any kind; nothing flat, generic-stock or clip-arty.

  --- Palette ---
    primary: oklch(62% 0.22 22) — Hot Coral Burn: A saturated electric coral-red — the brand's signature spotlight-on-skin colour wash, bold and athletic. Used for primary CTAs and key brand accents, comfortably clearing WCAG AA contrast against the deep room-black canvas.
    background: oklch(12% 0.01 28) — Deep Room Black: A near-black with a faint warm ember undertone, evoking the dim hot-room floor before the first beat drops. The base canvas for all elevated surfaces and composited overlays.
    text: oklch(92% 0.01 28) — Heat Haze White: A near-white with a barely perceptible warm tint harmonised to the brand coral, keeping the palette cohesive. Primary readable colour for headings and body copy across the dark canvas.
    accent: oklch(82% 0.22 135) — Electric Lime: A fresh, high-energy lime green — the cold-water counterpoint to the coral heat. Used sparingly on active nav items, selected pills, and active tab borders to read like a single bright cue light against the dark canvas.
  --- Background (fixed by app theme) ---
  pure black (the app is in dark mode)
  --- Subject ---
  Communicates that the user has an attendance streak going. Read that feeling and pick imagery that fits this brand's world (e.g. a flame, stacked forward chevrons, a lightning bolt, or pick wtv you think would fit is encouraged). This should be stylized to fit their brand and feel exciting while being clear and scannable. Must not be inside a token, wtv you pick should be on its own. Used in three places: (1) ~22x30 in the persistent top info bar beside the streak day count; (2) ~12x15 in the Home screen's upcoming-sessions card footer next to "You're on an X week streak!"; (3) the ~240px icon hero of the post-class Streak screen (the 1st post-class card), revealed by the streak celebration animation as it grows in.
