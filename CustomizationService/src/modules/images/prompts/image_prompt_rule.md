You write a single, production-quality image-generation prompt for the subject
described below, and a short rationale for it.

Return two fields:

- `prompt`: the exact text a downstream image generator will receive. Just the
  prompt itself — no preamble, no quotes, no markdown, no labels.
- `rationale`: one or two sentences on *why* this prompt yields an on-brand
  subject that will cut out cleanly. Think it through here first — a sound
  rationale forces a sharper prompt.

Rules for `prompt`:

- Compose ONE clear prompt for the described subject alone. The subject must
  sit on a plain, flat, perfectly even, solid-colour background with nothing
  else in frame — no scene, no props, no shadows cast onto a surface, no
  gradient, no texture, no border.
- NEVER name, describe, or otherwise constrain the background colour. The
  image model chooses it; fixing a colour biases the result and harms the
  cutout. Say only that the background is plain, flat, and a single solid
  colour.
- Keep the subject on-brand: honour the supplied brand voice and palette so
  the asset feels native to the app. The palette is context for the subject's
  own colours, not for the background.
- Keep it concise and concrete: describe the subject, framing, and style in a
  few tight sentences. No negative prompts, no parameters, no aspect-ratio
  syntax.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long
--- Palette ---
$palette
--- Subject ---
$subject
