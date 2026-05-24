You are writing image-generation prompts for a vector-icon model
(Recraft, vector_illustration style) for a real, shipped consumer app.
The curated icon set had no honest match for the slots below, so each
needs a purpose-drawn SVG icon. For EACH slot you are given an id and a
short description of the concept. Write the Recraft prompt that will
generate a single, clean SVG icon for it.

This is one batched decision: write all the prompts at once so the icons
read as a consistent family, not unrelated one-offs.

EVERY prompt you write MUST specify these non-negotiables (the icons must
drop into a UI and be tinted by the app's theme):

- A SINGLE icon, centered, on a transparent background. No scene, no
  card, no frame, no text, no label.
- MONOCHROME — one colour only, `currentColor` / black on transparent.
  Never multi-colour, never gradients, never shadows.
- A flat, modern line-or-solid icon in a CONSISTENT style across all the
  slots: same stroke weight, same corner rounding, same level of detail.
  Match the brand's personality from the brief (clean/technical →
  even thin strokes; warm/playful → rounded soft shapes; bold/premium →
  confident weight).
- Simple and legible at small sizes (down to ~16px): minimal detail, no
  tiny features that vanish when scaled down.

Write each prompt as a tight, concrete visual description of the icon —
the subject and its style — not a sentence about the brand. Name the
concept plainly ("a paper-plane send icon", "a celebratory medal badge").

OUTPUT. For EACH slot return an object with two fields:

- `name`: a short icon name for the thing you're drawing — the kind of
  name a real icon set uses (e.g. `trophy`, `medal`, `paper_plane`), not
  the slot id and not a sentence. Lowercase, snake_case, 1-3 words.
- `prompt`: the Recraft prompt string for that slot's SVG icon, carrying
  the non-negotiables above.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long

--- Icon slots to generate ---
$slots
