# Lottie Helper

A standalone tool for authoring Lottie recolour presets: preview/tune popup
animations, group their colours, and decide the recolour.

Self-contained — does **not** depend on CustomizationService or any other system.

## What it does

- **Preview & tune** a popup animation: load a Lottie + a reveal image, loop it,
  and set the `insertion_point` (frame + centre x/y + size), `speed`, and
  `hold_seconds`. Mirrors the app's reveal (scale 0.5→1 + fade, 260ms ease-out).
  The image pops in at `frame`, holds for `hold_seconds`, then the image and the
  animation end together (the animation is cut short if the hold expires first).
- **Pause before loop** (`pause` slider): a preview-only beat that freezes the
  final frame before restarting so the end state is readable. Not emitted to YAML.
- **Colour groups**: clusters the file's colours (solids + gradient stops) into
  groups with a tunable `merge` threshold. Each group gets a swatch (recolour it
  live), a name, and a description — these become the preset's `recolor_regions`,
  each with the literal `layers` (the Lottie `nm` names) the colour lives on.
- **YAML**: drafts a standalone per-animation `config.yaml` (top-level
  id/display_name/description/file/types/speed + `recolor_regions` with names,
  descriptions, and the real `layers` field the pipeline bakes onto, plus
  `insertion_point.hold_seconds` for reveal presets). Save it as
  `assets/lottie_animations/<id>/config.yaml`, beside the animation `.json`
  (`file` is the bare json filename, relative to that folder) — not a block under
  a `presets:` list.

## How rendering & recolour work

- Renders through the **official dotLottie web player** (`@lottiefiles/dotlottie-web`).
- Recolour is done by **mutating the animation JSON** (clone → rewrite the
  matching fill/stroke/gradient colours → re-render the copy). It does **not**
  use slots / `setThemeData` — that path crashes on multi-gradient files in
  dotlottie-web 0.74.0 (see `dotlottie-web-gradient-slot-bug.yaml`). Mutation
  recolours solids and gradients reliably, and mirrors what the pipeline does:
  bake a recoloured copy per tenant (like icons), then just play it.

## Run it

```
npm install
npm run dev      # dev server with hot reload (prints a localhost URL)
npm run build    # production bundle -> dist/
npm run preview  # serve the built dist/
make dev         # same as npm run dev
```

Vite app. The dotLottie wasm loads from a CDN on first open (needs internet).
