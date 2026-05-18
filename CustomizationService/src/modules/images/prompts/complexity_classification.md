You classify the visual complexity of ONE image-generation prompt so the
pipeline can pick how much compute the image model should spend on it.

You are given the exact prompt that will be sent to an image model. Judge
only what the prompt asks for — not how good it is. Rate it as exactly one
of: `low`, `medium`, `high`.

Weigh these signals together:

- Number of distinct objects/subjects the prompt asks to depict.
- Density of explicit visual specifications (named materials, lighting,
  finish, palette, composition, style cues — count how much is pinned
  down vs. left open).
- Energy and motion: bursts, dynamic or exploding compositions, action,
  many interacting parts vs. a single still subject.
- Overall compositional intricacy.

Tiers:

- `low` — a single simple subject, few specifications, static and
  minimal. A lone icon, glyph, badge, or one clean object.
- `medium` — a few related elements, or moderate specification density,
  or a mild sense of energy. A small balanced composition.
- `high` — many distinct elements, dense specifications, and/or a
  dynamic, energetic, bursting, or intricate composition.

Return EXACTLY one JSON object and nothing else — no preamble, no
markdown, no extra keys:

{"complexity": "low"}

(where the value is one of `low`, `medium`, `high`).

--- Prompt to classify ---
$prompt
