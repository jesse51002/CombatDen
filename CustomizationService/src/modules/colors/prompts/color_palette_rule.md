You are choosing a realistic, production-quality app colour palette and
expressing it the way a senior design system does.

For EACH colour slot you are given an id and a human description. Decide
the slot's visual ROLE from its description alone (never from its id):

- If the description indicates the base surface (background, canvas,
  sheet) or the primary readable text: keep it SIMPLE and realistic.
  These are NEAR-NEUTRAL, LOW-CHROMA colours — not vivid, not "designed".
- If the description indicates an accent, primary, brand, highlight,
  badge, or similar emphasis role: it MAY be saturated and interesting,
  but must stay coherent with the brand and look like a real app, not a
  swatch demo. Restraint wins: one confident accent beats three competing
  ones.

Express every colour in OKLCH, as three numbers:

- `l`: lightness, a number from 0 to 1 (0 = pure black, 1 = pure white).
  Think of this the way you think of `L%` in CSS, but as a decimal —
  62% becomes `0.62`.
- `c`: chroma, a number from 0 to about 0.4. Lower = more neutral / grey;
  higher = more saturated / vivid.
- `h`: hue angle in degrees, 0–360 (0 ≈ red, 60 ≈ yellow, 120 ≈ green,
  240 ≈ blue, etc.).

Example: a warm orange is roughly `{l: 0.62, c: 0.19, h: 28}`. OKLCH is
perceptually uniform, so reason in it deliberately: to make a colour
darker or lighter, change `l`; to make it more or less vivid, change `c`.

Colour craft rules (these are how good systems avoid amateur output):

- Reduce chroma as `l` approaches 0 or 1. High chroma at the extremes
  looks garish and cheap.
- NEVER use pure gray or pure black. A neutral with chroma exactly 0
  feels lifeless. Give every neutral a tiny chroma (about 0.005–0.015)
  hued toward the brand colour — small enough not to read as tinted, big
  enough to create subconscious cohesion with the brand.
- The base background surface and the primary readable text must be
  low-chroma: chroma between 0.003 and 0.04. The background must sit
  inside a band off BOTH pure extremes: in a dark theme its `l` is
  between 0.08 and 0.30 (near-black but never pure black); in a light
  theme its `l` is between 0.86 and 0.90 (near-white but never pure
  white). The text stays near-white (`l` at or above 0.85) in a dark
  theme and near-black (`l` at or below 0.40) in a light theme. The
  background band matters because the client builds elevated surfaces
  (cards, sheets) by compositing a translucent overlay over the resolved
  background — a background flush against black or white leaves no tonal
  room for that elevation to read.
- The readable text colour MUST meet WCAG AA contrast — at least 4.5:1
  for normal text — against the base background colour. Reason about the
  contrast deliberately by widening the lightness gap; do not eyeball it.
- Every colour in this palette — not only the `text` slot — may end up
  rendered AS text against the background somewhere in the app: an active
  tab label, an icon, a link, a price, a price-change delta. When you
  choose any non-background colour (primary, accent, brand, highlight,
  etc.), assume it will be set directly on the canvas and pick a value
  that also clears WCAG AA (≥ 4.5:1) against the background. The
  deterministic contract enforces this only for the `text` slot; for
  everything else, this prompt is the only check. The simplest way to
  satisfy it is to keep enough lightness gap between the colour and the
  background — a vivid hue that lives at a similar lightness to the
  canvas will fail.

  **Override.** If the colour brief explicitly asks for a deliberately
  low-contrast tone for a specific slot (for example "washed-out subtle
  accent", "ghost watermark colour"), respect the brief — the user's
  intent wins over this default. When you do, quote the phrase from the
  brief that you are honouring in that slot's `description`, so the
  intent is preserved in the artifact.

For EACH slot return an object with three fields:

- `oklch`: a structured object `{l: <number>, c: <number>, h: <number>}`
  with the channel meanings above. (`alpha` is supported but pipeline
  base slots are always opaque — omit it.)
- `display_name`: a short, evocative human label for the colour itself
  (for example "Warm Ash Cream", "Editorial Magenta") — a name, not a
  sentence.
- `description`: one or two sentences on what the colour is and how it
  is used in the app.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long
Colour direction: $colour_direction
Dark mode: $dark_mode

--- Colour slots to fill ---
$slots
