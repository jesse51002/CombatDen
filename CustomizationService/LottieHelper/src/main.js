import { DotLottie } from '@lottiefiles/dotlottie-web';

// Use dotlottie-web's default CDN wasm (version-matched to the JS glue —
// a vendored copy from node_modules mismatched and crashed setThemeData with
// a wasm "function signature mismatch"). Needs internet on load.

"use strict";

let anim = null;          // DotLottie instance (canvas + thorvg/wasm)
let firstFrame = 0;       // 0 for dotLottie (frames are 0..totalFrames-1)
let totalFrames = 0;
let colorGroups = [];     // [{key, avgHex, count, members:Set<hex>, suggested}]
let currentFrame = 0;     // current playback frame (0-based)
let originalData = null;  // pristine parsed Lottie JSON — recolor source of truth
let loadedName = null;    // filename, for the status line
let freshLoad = false;    // true only on a new file load
// ---- playback-cycle state (manual loop: reveal hold + pre-loop pause) ------
// We drive looping ourselves (dotLottie loop is off) so we can hold the
// revealed image for `hold` seconds — ending the animation early when the hold
// expires — and then sit on the final frame for `pause` seconds before
// restarting, so the end state is readable instead of snapping back instantly.
let holdTimer = null;     // fires endCycle() when the reveal hold elapses
let loopTimer = null;     // fires restartCycle() after the pre-loop pause
let revealStarted = false;// hold already started this cycle (one-shot per loop)
let cycleEnded = false;   // image dismissed + animation halted, awaiting restart
const groupOverrides = {};// group key -> new hex (live recolour)
const groupNames = {};    // group key -> user-typed region name
const groupDescs = {};    // group key -> user-typed region description

const $ = (id) => document.getElementById(id);
const stage = $("stage");
const overlay = $("overlay");
const revealBox = $("revealBox");

// ---- value helpers -------------------------------------------------------
const sliders = {
  frame: $("frame"), x: $("x"), y: $("y"), w: $("w"), h: $("h"),
  speed: $("speed"), hold: $("hold"), pause: $("pause"),
};
const outs = {
  frame: $("frameOut"), x: $("xOut"), y: $("yOut"), w: $("wOut"), h: $("hOut"),
  speed: $("speedOut"), hold: $("holdOut"), pause: $("pauseOut"),
};
const val = (k) => parseFloat(sliders[k].value);
const fmt = (n) => (Number.isInteger(n) ? String(n) : n.toFixed(3).replace(/0+$/, "").replace(/\.$/, ""));
const threshVal = () => parseFloat($("thresh").value);

function syncOuts() {
  outs.frame.textContent = String(Math.round(val("frame")));
  outs.x.textContent = fmt(val("x"));
  outs.y.textContent = fmt(val("y"));
  outs.w.textContent = fmt(val("w"));
  outs.h.textContent = fmt(val("h"));
  outs.speed.textContent = fmt(val("speed"));
  outs.hold.textContent = fmt(val("hold")) + "s";
  outs.pause.textContent = fmt(val("pause")) + "s";
}

// ---- reveal positioning (mirrors _PlacedReveal: left=x*w, top=y*h, etc.) --
// UI x/y are the image CENTER (0..1). The app/YAML use a top-left corner, so
// we convert: cornerLeft = centerX - width/2. cornerLeft() is reused by the
// YAML emitter so the preview and the emitted preset stay identical.
function cornerLeft() { return val("x") - val("w") / 2; }
function cornerTop() { return val("y") - val("h") / 2; }

function positionOverlay() {
  const sw = stage.clientWidth;
  const sh = stage.clientHeight;
  for (const el of [overlay, revealBox]) {
    el.style.left = (cornerLeft() * sw) + "px";
    el.style.top = (cornerTop() * sh) + "px";
    el.style.width = (val("w") * sw) + "px";
    el.style.height = (val("h") * sh) + "px";
  }
}

// reveal frame is stored absolute (matches YAML); compare against relative current.
const insertionRel = () => Math.round(val("frame")) - firstFrame;
const hasReveal = () => !!overlay.getAttribute("src"); // an image is loaded to reveal

function updateRevealVisibility() {
  const hasImg = hasReveal();
  overlay.style.display = hasImg ? "block" : "none";
  if (!hasImg) { overlay.classList.remove("revealed"); return; }
  // Once the hold has elapsed (cycleEnded) the image stays dismissed through the
  // pre-loop pause regardless of frame, so tuning sliders can't re-pop it.
  if (cycleEnded) { overlay.classList.remove("revealed"); return; }
  // Adding/removing .revealed plays / snaps-back the ScaleReveal pop.
  overlay.classList.toggle("revealed", currentFrame >= insertionRel());
}

// ---- manual loop controller ----------------------------------------------
const holdMs = () => Math.max(0, val("hold")) * 1000;   // reveal image dwell time
const pauseMs = () => Math.max(0, val("pause")) * 1000; // pre-loop freeze (preview only)
function clearCycleTimers() {
  if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
  if (loopTimer) { clearTimeout(loopTimer); loopTimer = null; }
}

// The reveal hold has elapsed (or, with no image, the animation finished):
// dismiss the image and halt playback wherever it is — this is the "ends early"
// cut — then schedule the next cycle behind the pre-loop pause.
function endCycle() {
  clearCycleTimers();
  cycleEnded = true;
  overlay.classList.remove("revealed");
  if (anim) anim.pause(); // freeze on the current frame so the end state is visible
  scheduleLoop();
}

function scheduleLoop() {
  if (!$("loopChk").checked) return; // loop off: stay frozen on the end state
  loopTimer = setTimeout(restartCycle, pauseMs());
}

function restartCycle() {
  loopTimer = null;
  revealStarted = false;
  cycleEnded = false;
  overlay.classList.remove("revealed");
  if (anim) { anim.setFrame(firstFrame); anim.play(); }
}

function refresh() {
  syncOuts();
  if (anim) anim.setSpeed(val("speed"));
  positionOverlay();
  updateRevealVisibility();
  renderYaml();
}

Object.values(sliders).forEach((s) => s.addEventListener("input", refresh));
$("outlineChk").addEventListener("change", (e) =>
  revealBox.style.display = e.target.checked ? "block" : "none");
// Looping is driven manually (see the cycle controller), so the checkbox only
// gates whether we restart after a cycle. Turning it on while frozen kicks off
// the next cycle immediately.
$("loopChk").addEventListener("change", (e) => {
  if (e.target.checked) { if (cycleEnded) restartCycle(); }
  else clearCycleTimers();
});
$("thresh").addEventListener("input", () => { $("threshOut").textContent = String(threshVal()); regroup(); });
window.addEventListener("resize", () => { positionOverlay(); });

// ---- colour walk ---------------------------------------------------------
// Visit every colour in the file as a read/write "handle", so solid fills/
// strokes (`fl`/`st`) AND gradient fills/strokes (`gf`/`gs`, whose stops live in
// a flat [pos,r,g,b,…] array) are recoloured uniformly. Covers layer shape trees
// plus precomp asset layers. Recolouring is a pure render-time change (clone →
// rewrite via handles → re-render); the file on disk is untouched.
const chan = (v) => Math.max(0, Math.min(255, Math.round(v <= 1 ? v * 255 : v)));
function toHex(arr) {
  if (!Array.isArray(arr) || arr.length < 3) return null;
  const h = (v) => ("0" + chan(v).toString(16)).slice(-2);
  return "#" + h(arr[0]) + h(arr[1]) + h(arr[2]);
}
const hexToUnit = (hex) => [parseInt(hex.slice(1, 3), 16) / 255, parseInt(hex.slice(3, 5), 16) / 255, parseInt(hex.slice(5, 7), 16) / 255];

// All the live [r,g,b,...] arrays for a solid colour property (static `k`, or
// every keyframe's `s` when animated).
function solidArrays(c) {
  if (c && c.a === 1 && Array.isArray(c.k)) return c.k.map((kf) => kf.s).filter(Array.isArray);
  return c && Array.isArray(c.k) ? [c.k] : [];
}
function makeSolidHandle(c) {
  const arrays = solidArrays(c);
  return {
    read: () => (arrays.length ? toHex(arrays[0]) : null),
    write: (hex) => { const u = hexToUnit(hex); for (const a of arrays) [a[0], a[1], a[2]] = u; },
  };
}
// A gradient stores its stops in a flat array: `g.k.k = [pos,r,g,b, pos,r,g,b,
// …, (opacity stops)]`. `g.p` = number of colour stops. One handle per stop.
function gradArrays(g) {
  const prop = g && g.k;
  if (!prop) return [];
  if (prop.a === 1 && Array.isArray(prop.k)) return prop.k.map((kf) => kf.s).filter(Array.isArray);
  return Array.isArray(prop.k) ? [prop.k] : [];
}
function makeGradientHandles(g) {
  const arrays = gradArrays(g);
  const stops = g.p || 0;
  const handles = [];
  for (let i = 0; i < stops; i++) {
    const b = i * 4; // [pos, r, g, b] per stop
    handles.push({
      read: () => (arrays.length && arrays[0].length >= b + 4 ? toHex([arrays[0][b + 1], arrays[0][b + 2], arrays[0][b + 3]]) : null),
      write: (hex) => { const u = hexToUnit(hex); for (const a of arrays) if (a.length >= b + 4) { a[b + 1] = u[0]; a[b + 2] = u[1]; a[b + 3] = u[2]; } },
    });
  }
  return handles;
}
function eachColorHandle(data, cb) {  // cb(handle, layerName)
  const walkShapes = (nm, shapes) => {
    if (!Array.isArray(shapes)) return;
    for (const s of shapes) {
      if (s && (s.ty === "fl" || s.ty === "st") && s.c) cb(makeSolidHandle(s.c), nm);
      else if (s && (s.ty === "gf" || s.ty === "gs") && s.g) for (const h of makeGradientHandles(s.g)) cb(h, nm);
      if (s && Array.isArray(s.it)) walkShapes(nm, s.it);
    }
  };
  const walkLayers = (layers) => {
    if (Array.isArray(layers)) for (const l of layers) if (l && l.shapes) walkShapes(l.nm, l.shapes);
  };
  walkLayers(data.layers);
  if (Array.isArray(data.assets)) for (const a of data.assets) if (a && a.layers) walkLayers(a.layers);
}
// ---- colour clustering ---------------------------------------------------
const hexToRgb = (hex) => [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
const rgbToHex = (rgb) => "#" + rgb.map((v) => ("0" + Math.round(Math.max(0, Math.min(255, v))).toString(16)).slice(-2)).join("");
const colorDist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

// Every distinct colour in the file (solids + gradient stops), with a usage
// count and the set of layer names that use it (for the group→layers mapping).
function collectColorData(data) {
  const counts = {};
  const layersByHex = {};
  eachColorHandle(data, (h, nm) => {
    const hx = h.read();
    if (!hx) return;
    counts[hx] = (counts[hx] || 0) + 1;
    if (typeof nm === "string" && nm.trim()) (layersByHex[hx] ||= new Set()).add(nm.trim());
  });
  const distinct = Object.entries(counts).map(([hex, count]) => ({ hex, count, rgb: hexToRgb(hex) }));
  return { distinct, layersByHex };
}

// Greedy clustering: process colours dominant-first; merge a colour into the
// nearest existing group if within `threshold` (RGB distance), else start a new
// group. Each group's colour is the count-weighted average of its members.
function clusterColors(distinct, threshold) {
  const sorted = [...distinct].sort((a, b) => b.count - a.count);
  const groups = [];
  for (const c of sorted) {
    let best = null, bestD = Infinity;
    for (const g of groups) {
      const d = colorDist(c.rgb, g.centroid);
      if (d < bestD) { bestD = d; best = g; }
    }
    if (best && bestD <= threshold) {
      best.items.push(c);
      best.total += c.count;
      const sum = [0, 0, 0];
      for (const it of best.items) for (let i = 0; i < 3; i++) sum[i] += it.rgb[i] * it.count;
      best.centroid = sum.map((s) => s / best.total);
    } else {
      groups.push({ items: [c], total: c.count, centroid: c.rgb.slice() });
    }
  }
  return groups.map((g) => {
    const members = new Set(g.items.map((it) => it.hex));
    return { key: [...members].sort().join(","), avgHex: rgbToHex(g.centroid), count: g.total, members };
  });
}

// Suggest a human name from the nearest basic colour (deduped per grouping).
const COLOR_NAMES = [
  ["black", [0, 0, 0]], ["white", [255, 255, 255]], ["gray", [128, 128, 128]],
  ["red", [220, 40, 40]], ["orange", [240, 150, 40]], ["yellow", [240, 220, 40]],
  ["green", [40, 180, 80]], ["teal", [40, 180, 170]], ["blue", [40, 90, 220]],
  ["purple", [140, 60, 200]], ["pink", [240, 80, 150]], ["brown", [140, 90, 50]],
];
function nearestColorName(rgb) {
  let best = "color", bd = Infinity;
  for (const [name, c] of COLOR_NAMES) { const d = colorDist(rgb, c); if (d < bd) { bd = d; best = name; } }
  return best;
}

// Recompute groups from the pristine data at the current threshold. Resets
// overrides + names (grouping changed) and assigns fresh suggested names.
function regroup() {
  for (const k in groupOverrides) delete groupOverrides[k];
  for (const k in groupNames) delete groupNames[k];
  for (const k in groupDescs) delete groupDescs[k];
  if (!originalData) { colorGroups = []; renderGroups(); renderYaml(); return; }
  const { distinct, layersByHex } = collectColorData(originalData);
  colorGroups = clusterColors(distinct, threshVal());
  const used = {};
  for (const g of colorGroups) {
    const base = nearestColorName(hexToRgb(g.avgHex));
    used[base] = (used[base] || 0) + 1;
    g.suggested = used[base] === 1 ? base : `${base}_${used[base]}`;
    // union of the layers that use any colour in this group (group→layers map)
    const layerSet = new Set();
    for (const m of g.members) for (const ln of layersByHex[m] || []) layerSet.add(ln);
    g.layers = [...layerSet].sort();
  }
  renderGroups();
  renderYaml();
}

// Map each group's override down to its member colours (original hex -> new).
function currentOverrides() {
  const o = {};
  for (const g of colorGroups) {
    const ov = groupOverrides[g.key];
    if (ov) for (const m of g.members) o[m] = ov;
  }
  return o;
}

// Live recolour by mutating the JSON (NOT slots): clone the pristine data,
// rewrite every overridden colour (solids + gradient stops), and re-render the
// recoloured copy through dotLottie. dotLottie just plays the data — we never
// call setThemeData, so the 0.74.0 gradient-slot bug is sidestepped entirely.
// This mirrors what the pipeline does: bake a recoloured copy, then render it.
function recolorReload() {
  if (!originalData) return;
  const map = currentOverrides();
  const data = JSON.parse(JSON.stringify(originalData));
  eachColorHandle(data, (h) => { const ov = map[h.read()]; if (ov) h.write(ov); });
  createAnim(data);
}

function renderGroups() {
  const ul = $("layers");
  ul.innerHTML = "";
  if (!colorGroups.length) {
    const li = document.createElement("li");
    li.className = "empty";
    li.textContent = "No fill/stroke colours found in this file.";
    ul.appendChild(li);
    return;
  }
  for (const g of colorGroups) {
    const li = document.createElement("li");
    const left = document.createElement("div");
    left.className = "layer-left";

    const sw = document.createElement("input");
    sw.type = "color";
    sw.className = "swatch";
    sw.value = groupOverrides[g.key] || g.avgHex;
    const shades = [...g.members];
    sw.title = `Group avg ${g.avgHex}, ${shades.length} shade(s): ${shades.join(", ")}. Change to recolour the whole group live.`;
    sw.addEventListener("input", () => { groupOverrides[g.key] = sw.value; recolorReload(); });

    const nameInput = document.createElement("input");
    nameInput.type = "text";
    nameInput.className = "region-name";
    nameInput.placeholder = g.suggested;
    nameInput.value = groupNames[g.key] || "";
    nameInput.addEventListener("input", () => { groupNames[g.key] = nameInput.value.trim(); renderYaml(); });

    const meta = document.createElement("span");
    meta.className = "group-meta";
    meta.textContent = shades.length > 1 ? `×${g.count} · ${shades.length} shades` : `×${g.count}`;

    // Per-group description — what this colour does; feeds recolor_regions and
    // gives the recolour agent something to map on.
    const descInput = document.createElement("input");
    descInput.type = "text";
    descInput.className = "region-desc";
    descInput.placeholder = "description — what this colour does (for the recolor agent)";
    descInput.value = groupDescs[g.key] || "";
    descInput.addEventListener("input", () => { groupDescs[g.key] = descInput.value.trim(); renderYaml(); });

    left.appendChild(sw);
    left.appendChild(nameInput);
    left.appendChild(meta);
    li.appendChild(left);
    li.appendChild(descInput);
    ul.appendChild(li);
  }
}

// ---- YAML generation (matches index.yaml field order + >- folded blocks) -
// Returns a `>-` folded scalar: the `>-` sits inline after the key, and every
// wrapped content line is prefixed with `contentIndent` (the continuation
// indent, two deeper than the key — matching index.yaml).
function foldBlock(text, contentIndent) {
  const words = (text || "").trim().split(/\s+/).filter(Boolean);
  const src = words.length ? words : ["TODO"];
  const lines = [];
  let line = "";
  for (const word of src) {
    if (line && (line.length + 1 + word.length) > 70) { lines.push(line); line = word; }
    else line = line ? line + " " + word : word;
  }
  if (line) lines.push(line);
  return ">-\n" + lines.map((l) => contentIndent + l).join("\n");
}

// Emit the standalone per-animation `config.yaml` (one preset per file,
// validated directly into `schema.lottie_library.LottiePreset`). It goes in
// the preset's own folder beside the `.json`:
//   assets/lottie_animations/<id>/config.yaml
//   assets/lottie_animations/<id>/<file>.json
// so `file` is the bare json filename (relative to the folder), and the
// top-level keys are NOT indented under a `presets:` list.
function renderYaml() {
  const id = $("pId").value.trim() || "preset_id";
  const name = $("pName").value.trim() || "Display Name";
  const file = $("pFile").value.trim() || "file.json";
  const desc = $("pDesc").value.trim() || "TODO: what this animation does.";
  const types = [];
  if ($("tStandalone").checked) types.push("standalone");
  if ($("tReveal").checked) types.push("reveal");
  const typeStr = types.length ? `[${types.join(", ")}]` : "[standalone]";

  let out = "";
  out += `id: ${id}\n`;
  out += `display_name: ${name}\n`;
  out += `description: ${foldBlock(desc, "  ")}\n`;
  out += `file: ${file}\n`;
  out += `types: ${typeStr}\n`;
  out += `speed: ${fmt(val("speed"))}\n`;
  out += `recolor_regions:\n`;
  if (colorGroups.length) {
    for (const g of colorGroups) {
      const rname = groupNames[g.key] || g.suggested;
      const rdesc = groupDescs[g.key] || `TODO: the ${g.avgHex} group (${g.count} uses) — what this colour does in the animation.`;
      out += `  - name: ${rname}\n`;
      out += `    description: ${foldBlock(rdesc, "      ")}\n`;
      // The actual Lottie layer names this colour group lives on — a real,
      // required field: the pipeline bakes the colour onto exactly these
      // layers. Empty until you load a file / name the layers (the schema
      // rejects an empty list, on purpose).
      const layers = g.layers && g.layers.length ? `[${g.layers.join(", ")}]` : "[]  # TODO: name the layer(s)";
      out += `    layers: ${layers}\n`;
    }
  } else {
    out += `  # load a Lottie to populate colour groups\n`;
  }
  if ($("tReveal").checked) {
    out += `insertion_point:\n`;
    out += `  frame: ${Math.round(val("frame"))}\n`;
    out += `  x: ${fmt(cornerLeft())}\n`;
    out += `  y: ${fmt(cornerTop())}\n`;
    out += `  width: ${fmt(val("w"))}\n`;
    out += `  height: ${fmt(val("h"))}\n`;
    // hold_seconds: how long the revealed image stays before it (and the
    // animation) end.
    out += `  hold_seconds: ${fmt(val("hold"))}\n`;
  }
  $("yaml").value = out;
}

["pId", "pName", "pFile", "pDesc", "tStandalone", "tReveal"].forEach((id) =>
  $(id).addEventListener("input", renderYaml));

$("copyYaml").addEventListener("click", () => {
  navigator.clipboard.writeText($("yaml").value);
  const b = $("copyYaml");
  const t = b.textContent; b.textContent = "Copied ✓";
  setTimeout(() => (b.textContent = t), 1000);
});


// ---- loaders -------------------------------------------------------------
$("lottieFile").addEventListener("change", (e) => {
  const f = e.target.files[0];
  if (!f) return;
  const reader = new FileReader();
  reader.onload = () => {
    let data;
    try { data = JSON.parse(reader.result); }
    catch (err) { $("status").textContent = "Not valid JSON: " + err.message; return; }
    loadFile(data, f.name);
  };
  reader.readAsText(f);
});

$("imgFile").addEventListener("change", (e) => {
  const f = e.target.files[0];
  if (!f) return;
  const reader = new FileReader();
  reader.onload = () => { overlay.src = reader.result; refresh(); };
  reader.readAsDataURL(f);
});

// ---- clear / remove loaded files -----------------------------------------
$("clearImg").addEventListener("click", () => {
  overlay.removeAttribute("src");
  overlay.classList.remove("revealed");
  $("imgFile").value = "";
  refresh();
});

$("clearLottie").addEventListener("click", () => {
  if (anim) { anim.destroy(); anim = null; }
  clearCycleTimers();
  revealStarted = false; cycleEnded = false;
  $("lottieFile").value = "";
  originalData = null; loadedName = null;
  firstFrame = 0; totalFrames = 0; currentFrame = 0;
  regroup(); // originalData is null → clears groups + renders empty
  $("status").textContent = "No animation loaded.";
  refresh();
});

// Render `data` (the pristine file, or a recoloured clone) through the dotLottie
// player. We hand it a fresh clone — dotLottie may mutate the object in place, so
// this keeps originalData pristine for the next recolour pass.
function createAnim(data) {
  if (anim) { anim.destroy(); anim = null; }
  clearCycleTimers();
  revealStarted = false;
  cycleEnded = false;

  // loop is OFF — we manage looping ourselves (reveal hold + pre-loop pause).
  anim = new DotLottie({
    canvas: $("lottie"),
    data: JSON.parse(JSON.stringify(data)),
    autoplay: true,
    loop: false,
    speed: val("speed"),
    renderConfig: { autoResize: true, devicePixelRatio: window.devicePixelRatio || 1 },
  });

  anim.addEventListener("load", () => {
    firstFrame = 0;
    totalFrames = anim.totalFrames || 0;
    const last = Math.max(0, Math.round(totalFrames) - 1);
    sliders.frame.min = "0";
    sliders.frame.max = String(last);
    if (freshLoad) {
      // default insertion frame to ~75% through (the app's lightning choreography)
      sliders.frame.value = String(Math.round(last * 0.75));
      freshLoad = false;
    }
    if (loadedName) {
      $("status").textContent =
        `Loaded ${loadedName} — ${Math.round(totalFrames)} frames, ${colorGroups.length} colour group(s).`;
    }
    refresh();
  });

  anim.addEventListener("frame", (e) => {
    currentFrame = e.currentFrame;
    updateRevealVisibility();
    // Start the reveal hold the first time we cross the insertion frame. When it
    // elapses the image and the animation end together (possibly cutting the
    // animation short — "ends early if it needs to").
    if (hasReveal() && !revealStarted && !cycleEnded && currentFrame >= insertionRel()) {
      revealStarted = true;
      holdTimer = setTimeout(endCycle, holdMs());
    }
  });

  // Animation reached its last frame (loop is off).
  anim.addEventListener("complete", () => {
    if (cycleEnded) return;
    if (hasReveal()) {
      // A reveal hold owns the cycle end. If the hold hasn't started yet (the
      // insertion frame is the very last frame), start it now; otherwise just
      // freeze on the final frame with the image up until the hold expires.
      if (!revealStarted) { revealStarted = true; holdTimer = setTimeout(endCycle, holdMs()); }
    } else {
      // Standalone: no image to hold — pause on the end state, then loop.
      endCycle();
    }
  });
}

// Fresh file: cluster colours (from pristine data), then render through dotLottie.
function loadFile(data, filename) {
  originalData = data;
  loadedName = filename;
  regroup(); // cluster colours at the current threshold + render the groups
  if (!$("pFile").value.trim()) $("pFile").value = "animations/" + filename;
  freshLoad = true;
  createAnim(originalData);
}

// initial paint
refresh();
