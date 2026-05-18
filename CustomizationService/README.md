# AI Customization Pipeline

Takes a brand brief, produces a fully customized app.

---

## How it works

Two YAMLs you write (`app.yaml`, `customization.yaml`), one the pipeline
produces (`output.yaml`). Customized surface: **images and colors.**

The colour step resolves every colour slot in one structured LLM call; the
image step then resolves each image slot end to end (prompt → generate →
background-remove → validate → crop), and the results are assembled into
`output.yaml`.

```mermaid
flowchart TD
    In["app.yaml + customization.yaml"]
    CBuild["colour step — build prompt: brief + colour slots"]
    CLLM["LLM — structured per-slot palette"]
    Palette["ColorPalette — hex per slot"]
    IBuild["image step, per slot — build image prompt: brief + slot + palette"]
    ILLM["LLM — structured ImagePrompt"]
    Classify["classify — structured Complexity → quality tier"]
    Gen["image generation (litellm image model, quality by tier)"]
    Raw["images/logo_primary.raw.png"]
    BgRemove["background removal — BackgroundService"]
    BgCheck["vision judge — structured BackgroundCheck"]
    Decide{"cutout clean?"}
    Crop["autocrop"]
    Fallback["keep un-removed raw"]

    In --> CBuild --> CLLM --> Palette --> IBuild --> ILLM --> Classify --> Gen --> Raw --> BgRemove --> BgCheck --> Decide
    Decide -- "yes" --> Crop
    Decide -- "no · retry ≤ bg_max_attempts" --> BgRemove
    Decide -- "attempts exhausted" --> Fallback

    classDef yaml fill:#e7f5ff,stroke:#1971c2,color:#0c2d4d
    class In yaml
```

> Entry point: `src/executor/orchestrator.py`. Provider choices
> (which model, which provider) are architecture, not pipeline
> logic — they're intentionally not in this diagram. Each call's
> model id is a per-call constant at the top of the module that
> makes the call (`color_service.py`, `image_service.py`,
> `complexity_service.py`, `background_service.py`), not a
> config/env knob; only secrets (API keys) stay in `config.py`.
> Image generation goes through a generic litellm generator, so the
> image model (`openai/gpt-image-2` today) is just one of those
> per-call constants — swapping providers is a one-line change. The
> background pass (remove → validate → crop) is its own
> `BackgroundService`. These constants are optional call overrides so
> dev bake-off scripts under `scripts/` can compare models.

---

## App-agnostic by construction

The pipeline knows nothing about any specific app. The slot list, slot
names, and slot descriptions live entirely in `app.yaml`. Point the same
pipeline code at a different `app.yaml` and you customize a different app
— no code changes, no rebuild, one new YAML directory.

That's the success criterion. The framework stays one codebase; every new
app is one new `apps/<app_id>/` folder.

---

## Shipped

```
codebase/AICustomizationPipeline/
├── schema/              # Pydantic contracts for the three YAMLs
│   ├── app_format, customization, primitives, slots
│   └── output/          # ColorOutput, ImageOutput, Output
├── src/
│   ├── __main__, cli            # entrypoint
│   ├── core/            # config, errors, run_context, imaging, logging
│   ├── executor/        # orchestrator (the pipeline), registry, writer
│   ├── modules/
│   │   ├── colors/      # ColorGenService, color_models, prompts/*.md
│   │   └── images/      # ImageGenService, image_models, prompts/*.md
│   └── shared/
│       ├── interfaces/  # LLMClient, ImageGenerator, BackgroundRemover
│       └── services/    # LiteLLMClient, BflImageGenerator,
│                        #   PhotoRoomBackgroundRemover, prompts/*.md
├── tests/               # core, modules, pipeline, services
└── apps/
    ├── combatden/       # app.yaml, customization.yaml, output.yaml
    └── smoketest/       # app.yaml, customization.yaml
```

`make test` runs the suite; `make smoke` runs the pipeline end to end on
`apps/smoketest/`. Entry point: `src/executor/orchestrator.py`. Read the
schemas for the exact YAML shapes; read `apps/combatden/` for a worked
example.

---

## Roadmap / TODO

The first real end-to-end run validated quality and style: the prompts
produce genuinely strong, style-consistent outputs. The remaining gaps are
**speed** (slot resolution is sequential), a **style** safety net, and a
**tighter crop**. Nothing below is implemented yet.

### 1. DAG execution engine with bounded concurrency

The pipeline is correct but slow because the executor resolves slots one
at a time. Replace the hand-rolled orchestrator with a dependency DAG that
runs each level in parallel (a bounded gather). Module-level atomicity is
already in place, which makes this tractable — but it is still the larger,
more intricate piece of work, and the prerequisite for the speed win:

- **One node per unit of work.** Each image gets its **own node class** —
  not a single `ImageGenService` reused via different `run(...)` args.
- **Typed contracts.** Every node takes required, named inputs and returns
  a single Pydantic model (already true today), so inputs and outputs are
  predictable and validated at the boundary.
- **Explicit dependencies — not name-matched.** The engine does **not**
  infer edges from kwarg names. `color` is an automatic dependency of
  every image node. **Image→image** dependencies are declared by the
  user: an image node takes an optional
  `dependant_image: list[ImageOutput]` input carrying the outputs of the
  images it depends on, so one image can build on others.
- **Registry emits the node set.** The registry returns a dict of every
  node to run for the app; the engine levels them topologically and
  gathers each level concurrently.

### 2. Style-adherence validation + conditional edit (NOT quality)

Reinstate the image validation step that is currently bypassed — but
strictly scoped to **style adherence**, never quality:

- **Explicit non-goal: quality.** Judging "is this good enough" is a
  slippery slope that ends in unbounded regeneration. Do not do it.
- **In scope: does the image match the intended style?** A structured
  verdict on style alignment only.
- **On mismatch → edit, not regenerate.** If the image is off-style, fix
  it with an image **edit** (nano-banana / OpenAI image edit) toward the
  target style. A corrective alignment step, not a quality loop.

### 3. Tighter crop — grid-based transparency trim

The current autocrop (the first crop — `autocrop` in
`src/core/imaging.py`) gets stuck on **slightly-non-transparent fringe**:
faint low-alpha halo left by background removal keeps the bounding box
loose. Add a second, grid-based pass that runs **after** the existing
crop and trims those regions:

- Walk the already-cropped image as a grid of cells.
- For each cell, measure the share of non-zero-alpha pixels. If **≥90%**
  of the cell is effectively transparent, drop the cell.
- If a cell fails that check, look only at the pixels that *do* carry
  alpha and take their **average** alpha; if that average is **≤5%**,
  treat the cell as halo and remove it too.
- Re-crop tight to whatever survives.

This refines the existing crop — it does not replace it.
