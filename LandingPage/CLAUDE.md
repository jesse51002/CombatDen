# LandingPage

React-based marketing site rendered from `hifi/landing.jsx` and `hifi/pricing.jsx`.

## Copy rule (strict)

**No hardcoded user-visible text in JSX files.** Every string that renders to the user — headlines, eyebrows, body copy, button labels, placeholders, alt text, aria-labels, FAQ items, mock-UI labels, glyphs (→, +) — lives in the single `COPY` dict at the top of the file.

Why: this codebase has multiple viewport branches (mobile fallback vs. sticky desktop in `HowItWorks`, `DualBenefit`, `ResultBlock`, etc.). Every time a string was duplicated across branches, the two copies drifted. Centralizing in `COPY` removes the failure mode entirely and gives one place to edit copy.

How to apply:
- Adding a new string? Add a key to `COPY` and reference it in JSX. Never inline a literal.
- Editing copy? Edit `COPY` only. The JSX should not need to change.
- Adding visual config (image paths, icons, layout flags) that pairs with copy entries? Keep the visual config in a sibling array (e.g. `HOW_STEP_VISUALS`, `DUAL_BENEFIT_IMAGES`) and zip it into the COPY entries by index at render time. Don't put image paths inside `COPY`.
- Glyphs / decorative single characters (→, +) also live in `COPY.glyphs`. Treat them as text.

If you find yourself typing a string literal inside JSX, stop and put it in `COPY` first.

## Line breaks in copy (\n)

The App root in both `hifi/landing.jsx` and `hifi/pricing.jsx` sets `whiteSpace: "pre-line"`. Because CSS `white-space` is inherited, every `\n` inside a `COPY` string renders as a real line break, while runs of regular spaces still collapse normally. To force a line break in copy, just put `\n` in the string — no `<br />`, no extra wrapper element, no per-element `whiteSpace` override.

If a specific element needs the opposite behavior (e.g. a button label that should never wrap), it must override locally — `whiteSpace: "nowrap"` on the element keeps doing what it always did.
