# Spec: Lottie recolor-bake + per-animation library + new render args

> **Status:** implementation spec for a follow-up agent. Self-contained — it
> names every file to touch and quotes the patterns to mirror. It describes the
> work; it does not perform it.

---

## 1. Context — why this change

Today the pipeline is **selective, not generative** for Lottie. `LottieNode.run()`
(`src/modules/lotties/lottie_node.py`) picks a preset and runs one LLM call to map
each region → a **palette role *name*** (e.g. `{"bolt": "primary"}`). It writes
**no file**; the Flutter app recolors at render time against its live palette
(`../CustomizationEngine/lib/theme/lottie/theme_lottie.dart` → `_regionDelegates`).

We are inverting that. The pipeline will **bake a fully-recolored per-tenant
`.json`** into the run output dir — exactly like icons are copied into `icons/`.
The rendering side then **just plays the baked file and never recolors again.**

Alongside the bake, four structural changes:

- **Per-animation folders.** Drop the single `index.yaml` list. Each animation
  gets its own folder (like icon sets) holding the `.json` + a `config.yaml`
  next to each other. Easier to manage/expand than one 2000-line file.
- **Standalone schema.** The Pydantic model becomes a single per-file instance,
  not a `presets: list`.
- **New YAML args** flow through schema → bake → output wire → app: `speed`
  (playback multiplier) and `hold_seconds` (reveal: image holds N s, then image
  AND animation end — cut short if needed). Plus `layers` is promoted from a
  comment to a real, **complete** field per region.
- **LottieHelper** (the authoring tool at `LottieHelper/`) emits the new
  standalone format and its `layers` extraction is fixed to list every layer in a
  colour group.

**Outcome:** one curated animation = one folder (`config.yaml` + `.json`). The
pipeline resolves region→role→colour, recolours the named layers in the JSON,
writes the baked JSON into the run, and the app plays it with `speed`/
`hold_seconds` behaviour and zero recolour logic.

> Note: the assets are **already partly migrated** — `assets/lottie_animations/`
> now holds `lightning/` (`config.yaml` + `lightning_neon.json`) and
> `circle_checkbox/` (`checkbox.json`, no config yet), and `lightning/config.yaml`
> already carries `speed`, `insertion_point.hold_seconds`, and a `# layers: bolt`
> comment. The **schema + loader have NOT caught up** (they still load
> `index.yaml` into `LottieLibrary.presets`, and `extra="forbid"` would reject
> `speed`/`hold_seconds`). This spec brings them in line.

---

## 2. Current-state file map (grounding)

All paths are relative to `CustomizationService/` unless prefixed `../`.

| Area | File | What it does now |
|---|---|---|
| Node | `src/modules/lotties/lottie_node.py` | `run()`: `candidates()` → selection → recolor (role names) → returns `LottieOutput`. No file I/O. |
| Recolor | `src/modules/lotties/lottie_recolor_service.py` | One structured LLM call → `dict[region → palette_key]`. No JSON mutation. |
| Selection | `src/modules/lotties/lottie_selection_service.py` | LLM picks one preset id from candidates → returns `LottiePreset`. |
| Loader | `src/modules/lotties/lottie_library.py` | `LottiePresetLibrary.load()` reads `<root>/index.yaml` → `LottieLibrary` → `_by_id`. `candidates(type)`, `get(id)`. `LOTTIE_LIBRARY_ROOT`, `LOTTIE_INDEX_FILENAME`. |
| Schema | `schema/lottie_library.py` | `LottieLibrary{presets: list[LottiePreset]}`, `LottiePreset{id,display_name,description,file,types,recolor_regions,insertion_point?}`, `RecolorRegion{name,description}`, `InsertionPoint{frame,x,y,width,height}`. All `extra="forbid"`. |
| Output | `schema/output/lottie_output.py` | `LottieOutput{preset_id,preset_file,display_name,region_roles,reveals?,insertion_point?}`, `extra="ignore"`. |
| Run dirs | `src/core/run_context.py` | `IMAGES_DIRNAME/FINAL_IMAGES_DIRNAME/ICONS_DIRNAME`, `icon_path(slot)->AbsolutePath`, mkdir per dir. No lottie dir. |
| Icon bake (model to mirror) | `src/modules/icons/icon_matching_service.py` `_copy_matched()` | `dest = run_ctx.icon_path(slot)`, `shutil.copyfile(src,dest)`, returns `IconOutput(path=...)`. |
| Icon-set loader (model to mirror) | `src/shared/services/local_icon_set_catalog.py` `_load()` | globs `<root>/*/set.yaml`, validates each into `IconSetCatalogEntry`, indexes by id. `SET_MANIFEST_NAME="set.yaml"`. |
| Colour | `schema/output/color_value.py`, `schema/primitives.py` `RgbColor` | Palette value = `ColorValue{oklch,hsl,rgb,hex}`; `rgb.{r,g,b in 0..255, alpha?}`. |
| Path type | `schema/primitives.py` `AbsolutePath` | RootModel[str], must start `/`. Stored absolute in `output.yaml`. |
| API wire | `src/api/schema/output_response.py` `LottieWire{url,region_roles,reveals?,insertion_point?}` | Builds `lotties[slot]` with `url=/apps/{app}/{run}/lotties/{slot}`. |
| Render base | `../CustomizationEngine/lib/theme/lottie/theme_lottie.dart` | `Lottie.network(url, delegates:_regionDelegates(regionRoles))` override path; `Lottie.asset(fallback, delegates:_wildcardTint())` fallback. `resolve()` builds `LottieOverride`. |
| Render reveal | `../CustomizationEngine/lib/theme/lottie/theme_reveal_lottie.dart` | `Stack[ ThemeLottie(child0), if(_revealed) _PlacedReveal(child1) ]` (animation already BEHIND image). `_ctrl.duration=composition.duration; forward()`. Reveal at `_ctrl.value>=_revealAt`. No speed, no hold. |
| Render override model | `../CustomizationEngine/.../lottie_override.dart` | `LottieOverride.fromJson{url,region_roles,reveals,insertion_point}`. |
| Helper | `LottieHelper/src/main.js`, `LottieHelper/index.html` | Authoring tool: colour groups, `g.layers` union, emits a `- id:` list block with `# layers:` comment, `speed`, `insertion_point.hold_seconds`. |
| Consumers of library | `src/executor/registry.py` (`load()` once/run), `lottie_node.py`, `lottie_selection_service.py`, `lottie_recolor_service.py`, `src/api/config.py` (`lottie_library_root`), `tests/test_pipeline.py` | enumerated for change impact. |

---

## 3. Work items (dependency order)

### WI-1 — Library restructure: per-animation folders, drop `index.yaml`

**Asset layout** (mirror `assets/icon_sets/<id>/set.yaml` + `icons/`):
```
assets/lottie_animations/
  <preset_id>/
    config.yaml        # the per-animation preset (was one entry in index.yaml)
    <animation>.json   # the lottie, next to its config
```
- Add `config.yaml` for `circle_checkbox/` (currently has only `checkbox.json`).
- Normalize `lightning/config.yaml`: `id: lightning` (snake_case folder id), and
  `file: lightning_neon.json` (filename **relative to its own folder**, not
  `animations/...`).

**Schema** (`schema/lottie_library.py`): `LottiePreset` becomes the per-file
model loaded directly (like `IconSetCatalogEntry`). **Remove** the `LottieLibrary`
list wrapper and its `_unique_preset_ids` validator (uniqueness now = unique
folder names). Keep `LottiePreset`/`RecolorRegion`/`InsertionPoint`/`LottieType`.

**Loader** (`src/modules/lotties/lottie_library.py`): replace `load()` with a
folder scan mirroring `LocalIconSetCatalog._load()`:
```python
LOTTIE_CONFIG_FILENAME = "config.yaml"   # replaces LOTTIE_INDEX_FILENAME
# load(): for cfg in sorted(root.glob(f"*/{LOTTIE_CONFIG_FILENAME}")):
#             preset = LottiePreset.model_validate(yaml.safe_load(cfg.read_text()))
#             by_id[preset.id] = preset   # raise on dup id
```
Keep `candidates(type)` and `get(id)` byte-identical — consumers don't change.
**`file` resolution changes:** `preset.file` now resolves against the preset's
own folder (`<root>/<id>/<file>`), not the library root. Carry the folder/dir on
the loaded preset (e.g. a non-serialized `_dir`, or resolve at load and store an
absolute json path the bake step and the API delivery route can use).

**Impacted consumers:** `registry.py` (no change beyond the new loader),
`src/api/config.py` `lottie_library_root` (unchanged path; but the preset-file
delivery route, if it serves library files, must resolve per-folder).

**Tests** (`tests/test_pipeline.py`): build per-folder `config.yaml` fixtures
instead of an `index.yaml` list; the round-trip now validates each `config.yaml`
into `LottiePreset`.

### WI-2 — Schema additions: `speed`, `hold_seconds`, `layers`

In `schema/lottie_library.py`:
- `RecolorRegion`: add `layers: list[str]` — the **literal Lottie layer names**
  (the `nm` strings, NOT snake_case-validated) whose colours belong to this
  region. **Required, non-empty** — the bake step needs it to know which layers
  to recolour.
- `LottiePreset`: add `speed: float = 1.0` (validator: `> 0`).
- `InsertionPoint`: add `hold_seconds: float` (validator: `> 0`). Reveal-only (it
  already only exists on reveal presets via the existing `model_validator`).

This makes the already-written `lightning/config.yaml` validate.

### WI-3 — Pipeline bake (core)

**RunContext** (`src/core/run_context.py`): add `LOTTIES_DIRNAME = "lotties"`,
`self.lottie_dir = self.run_dir / LOTTIES_DIRNAME`, its `mkdir`, and
```python
def lottie_path(self, slot_id: str) -> AbsolutePath:
    return AbsolutePath(str((self.lottie_dir / f"{slot_id}.json").resolve()))
```
(mirror `icon_path`).

**Bake service** — new `src/modules/lotties/lottie_recolor_bake_service.py` (or a
method on the recolor service). Inputs: the chosen `LottiePreset` (+ its resolved
json path), the `region_roles` map (region → palette key), the `ColorPalette`,
and `run_ctx`. Steps:
1. Load the preset JSON.
2. For each region: `palette.palette[role_key]` → `.rgb` → lottie floats
   `[r/255, g/255, b/255]`.
3. For each `layer.nm in region.layers`: recolour every solid fill/stroke
   (`ty:"fl"`/`"st"`, colour at `c.k`, static or `a:1` keyframed `s`) and every
   gradient fill/stroke (`ty:"gf"`/`"gs"`, stops in the flat `g.k.k` array,
   `g.p` colour stops) on that layer to the colour. Recurse nested group items
   (`it`) and precomp asset layers (`assets[].layers`).
4. Write the recoloured JSON to `run_ctx.lottie_path(slot_id)`.

> **Port the algorithm from the canonical implementation:** the JS in
> `LottieHelper/src/main.js` — `eachColorHandle`, `makeSolidHandle`/`solidArrays`,
> `makeGradientHandles`/`gradArrays` (`g.p` stops, `[pos,r,g,b]` per stop). The
> Python differs only in being **scoped to the region's named layers** instead of
> recolouring file-wide by hex.

**Where the write lives:** inside the service/node (like icons), **not** the
writer. `src/executor/writer.py` is unchanged — it just dumps `output.yaml`.

**LottieOutput** (`schema/output/lottie_output.py`): add
```python
path: AbsolutePath            # the baked, recoloured json in the run dir
speed: float                  # lifted from preset
hold_seconds: float | None = None   # reveal only, lifted from insertion_point
```
Keep `preset_id`/`preset_file`/`display_name` for provenance. **Open decision
(§4):** keep `region_roles` for provenance or drop it.

**LottieNode.run()**: after `region_roles` resolves, call the bake service, then
return `LottieOutput(..., path=run_ctx.lottie_path(slot), speed=preset.speed,
hold_seconds=preset.insertion_point.hold_seconds if reveal else None)`.

**expand/seed round-trip:** a seeded (already-done) node validates its saved
`output.yaml` group back into `LottieOutput`; the baked file persists in the run
dir, so `path` stays valid. Re-running (dirty) re-bakes. No special handling.

### WI-4 — Output API wire

`src/api/schema/output_response.py` `LottieWire`: **add** `speed: float`,
`hold_seconds: float | None`; **drop** `region_roles` (baked in now). Keep
`url`, `reveals`, `insertion_point`. Build from `LottieOutput`. The
`url=/apps/{app}/{run}/lotties/{slot}` route must serve the **baked file from the
run dir** (`run_ctx.lottie_dir`), not the library preset — find and point the
serving route there.

### WI-5 — Rendering side (`../CustomizationEngine`)

`theme_lottie.dart`:
- **Remove** `_regionDelegates` and the `delegates:` on the `Lottie.network`
  override path — the baked file is already coloured. (Open decision §4:
  keep `_wildcardTint` on the **bundled-asset fallback** path so an un-baked
  fallback still themes, or drop it.)
- **Apply `speed`**: `controller.duration = composition.duration ~/ speed`
  (2× speed ⇒ half duration). Plumb `speed` from the override.

`theme_reveal_lottie.dart`:
- **Implement `hold_seconds`:** once `_revealed`, start a `Timer(hold_seconds)`;
  on fire, stop the controller (freeze/end) and dismiss — cutting the animation
  short if it hasn't finished. Today the image holds indefinitely and the
  animation plays its full single pass.
- **Stack order is already animation-behind-image** (lottie = child 0, image =
  child 1) — this already satisfies the earlier "animation behind the image"
  ask; just confirm, no change.
- Apply `speed` to `_ctrl.duration` here too.

`lottie_override.dart`: drop `regionRoles`; add `speed`, `holdSeconds`; update
`LottieOverride.fromJson` / `ThemeLottie.resolve` to read the new wire fields.
`ScaleReveal`'s 260 ms pop-in is unrelated to `hold_seconds` — leave it.

### WI-6 — LottieHelper authoring tool (`LottieHelper/`)

- **Fix `layers` (important):** per colour group, emit the **complete** list of
  layer names whose colours belong to that group. Audit `eachColorHandle` /
  `collectColorData` / `regroup` in `src/main.js` so the per-group `g.layers`
  captures **all** contributing layers — including nested group items (`it`) and
  precomp asset layers — not a partial set. Verify on a multi-layer file.
- **Promote `layers` to a real YAML field** (`layers: [a, b]`), not a
  `# layers:` comment.
- **Change the emitted YAML (`renderYaml`) to the standalone per-animation
  `config.yaml` format** matching WI-1/WI-2: top-level `id`, `display_name`,
  `description`, `file` (the json filename), `types`, `speed`, `recolor_regions`
  (each `name`/`description`/`layers`), and `insertion_point` (incl.
  `hold_seconds`) for reveals. **Not** a `- id:` list item under `presets:`.
- `speed` and `insertion_point.hold_seconds` are already emitted — keep.
- Update `LottieHelper/README.md` to describe the standalone-config output.

---

## 4. Open decisions (resolve before/while implementing — don't silently assume)

1. **Alpha:** bake palette alpha into the lottie colour array, or write only
   `r,g,b` and leave the artwork's existing alpha/opacity untouched?
   *(Recommend: r,g,b only — palette alpha is a UI-system concern; the lottie's
   `o`/stop-opacity is the artist's intent.)*
2. **`region_roles` on `LottieOutput`:** keep for provenance/debug (unused
   downstream) or drop now that colour is baked? *(Recommend: keep, comment as
   provenance-only.)*
3. **Bundled-asset fallback tint:** keep `_wildcardTint` on the un-baked fallback
   path, or drop all delegates? *(Recommend: keep on fallback only.)*

---

## 5. Verification

- **Schema/loader:** `make test` — round-trip `lightning/config.yaml` + a new
  `circle_checkbox/config.yaml` into `LottiePreset`; assert the folder-scan
  loader returns both and `candidates(REVEAL)`/`candidates(STANDALONE)` are
  correct.
- **Bake:** run the pipeline on the demo app (`tests/data/apps/demo` /
  `apps/<app>`); assert `lotties/<slot>.json` exists, parses, and the named
  layers' `fl/st`/`gf/gs` colours equal the resolved palette colour. Cross-check
  against LottieHelper's live recolour for the same palette.
- **API:** `GET /apps/{app}/{run}/lotties/{slot}` returns the **baked** file;
  `LottieWire` carries `speed`/`hold_seconds`, no `region_roles`.
- **App:** build `../CustomizationEngine`; play a baked reveal — confirm no
  recolour delegates run, `speed` changes duration, the image holds
  `hold_seconds` then the animation ends, and the image renders in front.
- **Helper:** load a multi-layer `.json`; confirm each colour group lists **all**
  its layers; paste the emitted `config.yaml` into a folder and validate it with
  the pipeline schema.
