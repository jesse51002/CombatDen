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

Express every colour in CSS OKLCH: `oklch(L% C H)` — L is lightness as a
percentage (0–100%), C is chroma (~0 to 0.4), H is the hue angle
(0–360). Example: `oklch(62% 0.19 28)`. OKLCH is perceptually uniform, so
reason in it deliberately: to make a colour darker or lighter, change L;
to make it more or less vivid, change C.

Colour craft rules (these are how good systems avoid amateur output):

- Reduce chroma as L approaches 0% or 100%. High chroma at the extremes
  looks garish and cheap.
- NEVER use pure gray or pure black. A neutral with chroma exactly 0
  feels lifeless. Give every neutral a tiny chroma (about 0.005–0.015)
  hued toward the brand colour — small enough not to read as tinted, big
  enough to create subconscious cohesion with the brand.
- The base background surface and the primary readable text must be
  low-chroma: chroma between 0.003 and 0.04. In a dark theme the
  background is near-black (L at or below 30%) and the text is near-white
  (L at or above 85%); in a light theme the background is near-white (L
  at or above 92%) and the text is near-black (L at or below 40%).
- The readable text colour MUST meet WCAG AA contrast — at least 4.5:1
  for normal text — against the base background colour. Reason about the
  contrast deliberately by widening the lightness gap; do not eyeball it.

For EACH slot return an object with three fields:

- `oklch`: the colour as an `oklch(L% C H)` string.
- `display_name`: a short, evocative human label for the colour itself
  (for example "Warm Ash Cream", "Editorial Magenta") — a name, not a
  sentence.
- `description`: one or two sentences on what the colour is and how it is
  used in the app.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long
Colour direction: $colour_direction
Dark mode: $dark_mode

--- Colour slots to fill ---
$slots
