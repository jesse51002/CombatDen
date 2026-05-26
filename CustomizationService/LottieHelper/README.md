# Lottie Helper

A standalone tool for authoring Lottie recolour presets: preview/tune popup
animations, group their colours, and decide the recolour.

Self-contained — does **not** depend on CustomizationService or any other system.

## What it does

- **Preview & tune** a popup animation: load a Lottie + a reveal image, loop it,
  and set the `insertion_point` (frame + centre x/y + size) and `speed`. Mirrors
  the app's reveal (scale 0.5→1 + fade, 260ms ease-out).
- **Colour groups**: clusters the file's colours (solids + gradient stops) into
  groups with a tunable `merge` threshold. Each group gets a swatch (recolour it
  live), a name, and a description — these become the preset's `recolor_regions`.
- **YAML**: drafts an `index.yaml` preset block (id/name/file/types/speed +
  `recolor_regions` with names, descriptions, and the group→layer mapping).

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
