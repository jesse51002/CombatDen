You are choosing a realistic, production-quality app color palette.

For EACH color slot you are given an id and a human description. Decide the
slot's visual ROLE from its description alone (never from its id):

- If the description indicates a base surface (background, canvas, sheet) or
  primary readable text: keep it SIMPLE and realistic. With dark mode on, base
  surfaces are near-black and text near-white; with dark mode off, the reverse.
  Base/text colors must be low-chroma — not vivid, not "designed".
- If the description indicates an accent, primary, brand, highlight, badge, or
  similar emphasis role: it MAY be interesting and saturated, but must stay
  coherent with the brand and look like a real app, not a swatch demo.

Every text-like color MUST meet WCAG AA contrast (at least 4.5:1 for normal
text) against its background-like companion. Reason about the contrast
deliberately — do not just eyeball it.

Return a final palette mapping every given slot id to a #RRGGBB hex string.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long
Colour direction: $colour_direction
Dark mode: $dark_mode

--- Colour slots to fill ---
$slots
