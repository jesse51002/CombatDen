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

## Search the web for conventions before designing

When the design question is "how do good sites usually present X?" — pricing tiers, free trial messaging, plan badges, FAQ layouts, footer structures, signup flows, error states, empty states, billing copy, onboarding patterns — **search the web first.** Look at what proven SaaS companies actually ship (Vercel, Linear, Notion, Stripe, Dropbox, Slack, etc.). Don't guess.

Why: convention is a usability shortcut. Buyers pattern-match to layouts and copy they've seen elsewhere. Inventing a novel treatment for a normalized thing makes the page feel wrong even if it's "creative." Worse, guessing at conventions wastes iteration cycles when the right answer is already publicly documented across a dozen pricing pages.

How to apply:
- If the work is a normalized/conventional pattern, run a WebSearch + WebFetch a couple of real pricing pages before proposing a design.
- Quote the convention you found ("Vercel uses 'Free forever' embedded in the card description; Dropbox uses 'Try for free' as the CTA").
- Then make the call — sometimes the convention is wrong for this product, but you can only know that after seeing it.
- Skip the search for genuinely project-specific work (this product's unique mechanic, our brand voice, internal copy decisions). Convention search is for the parts every SaaS has.

## Dev server: assume it's already running

**Never spawn `serve.py` / `make serve` in the background to smoke-test.** The harness doesn't reliably reap backgrounded processes, and the leftover servers squat on port 4173 — next time the user runs `make serve`, it fails with "port taken" and they have to hunt down PIDs.

Default assumption: the user has `make serve` running in their own terminal. To verify a change, just point them at the URL (e.g. `http://localhost:4173/onepager/onepager.html`).

If you genuinely need the server running (e.g. for a Bash HTTP check), **ask first.** Don't background it yourself. If a smoke-test can be done by checking the filesystem (`ls`, `stat`, Read) instead of HTTP, prefer that.

## Line breaks in copy (\n)

The App root in both `hifi/landing.jsx` and `hifi/pricing.jsx` sets `whiteSpace: "pre-line"`. Because CSS `white-space` is inherited, every `\n` inside a `COPY` string renders as a real line break, while runs of regular spaces still collapse normally. To force a line break in copy, just put `\n` in the string — no `<br />`, no extra wrapper element, no per-element `whiteSpace` override.

If a specific element needs the opposite behavior (e.g. a button label that should never wrap), it must override locally — `whiteSpace: "nowrap"` on the element keeps doing what it always did.
