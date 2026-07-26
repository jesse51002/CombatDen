// motif.js — the scroll-driven 3D motif for the AI page.
//
// NOT a React component and not a Babel file: three.js ships as an ES module, so
// this loads as <script type="module"> alongside the Babel bundle. It exposes
// window.CDMotif.init(), which the page calls from a useEffect once React has
// mounted, because it measures real section geometry that does not exist before
// the first render.
//
// What it draws: a pair of ring-balls behind the hero that scale away as the page
// moves, and ONE form pinned to the viewport for the rest of the page, drifting
// from the right margin to the left while it changes shape section by section.
//
// It reads the DOM by data attribute, never by section class, so the sections can
// be renamed or reordered without touching this file:
//   [data-motif-hero]     the hero's own canvas host
//   [data-motif-section]   in document order, the sections the chain is keyed to
//
// See LandingPage/CLAUDE.md. Honors prefers-reduced-motion by rendering one static
// frame and never starting a loop.

import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

/*
  Every form is one closed path swept into a tube. Closed means no end caps,
  and a Catmull-Rom spline through the path means no corner is ever a corner.
  Nothing is assembled, so there is nothing to joint.

  Because every path is swept with the same segment counts, all of them share
  an identical vertex layout. That is what lets ONE mesh morph between them on
  the GPU rather than swapping geometry per section.

  Two layers only:
    - the hero pair, absolutely placed, which scales away as the page moves
    - one pinned form, fixed to the viewport, which scales in and then stays
      on screen for the whole page, changing shape section by section
*/
const ACCENT = 0x2a67bd;
const ACCENT_DARK = 0x1f5099;
const TUBULAR = 260;
const RADIAL = 24;
const TAU = Math.PI * 2;
const V = (x, y, z) => new THREE.Vector3(x, y, z);
const clamp01 = (n) => Math.min(1, Math.max(0, n));
const easeOut = (n) => 1 - Math.pow(1 - n, 3);

/*
  Compresses a segment's progress into a short window at its centre, so each
  form is held for most of the scroll and the change happens fast. A blend of
  two knots is a knot of neither, and spreading that hybrid across a whole
  section is what made the middle of every transition read as a mistake.
  SNAP_WINDOW is the share of the segment spent actually changing.
*/
const SNAP_WINDOW = 0.44;
const snap = (x) => {
  const t = clamp01((x - (0.5 - SNAP_WINDOW / 2)) / SNAP_WINDOW);
  return t * t * (3 - 2 * t);
};
const reduceMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)"
).matches;

function sample(count, span, fn) {
  const pts = [];
  for (let i = 0; i < count; i++) pts.push(fn((i / count) * span));
  return pts;
}

/*
  Every form is an exact named space curve, taken from the standard
  parametrisations rather than drawn by hand.

  All three are resampled to the same count at uniform arc length, so
  corresponding points travel comparable distances when morphing instead of
  bunching up, and no form swells partway through a transition.
*/
const V3 = {
  add: (a, b) => a.map((v, i) => v + b[i]),
  sub: (a, b) => a.map((v, i) => v - b[i]),
  mul: (a, k) => a.map((v) => v * k),
  len: (a) => Math.hypot(a[0], a[1], a[2])
};

function resample(pts, n) {
  const cum = [0];
  for (let i = 1; i <= pts.length; i++) {
    cum.push(cum[i - 1] + V3.len(V3.sub(pts[i % pts.length], pts[i - 1])));
  }
  const total = cum[pts.length];
  const out = [];
  let j = 0;
  for (let i = 0; i < n; i++) {
    const d = (i / n) * total;
    while (j < pts.length && cum[j + 1] < d) j++;
    const seg = cum[j + 1] - cum[j] || 1;
    const t = (d - cum[j]) / seg;
    const a = pts[j % pts.length];
    const b = pts[(j + 1) % pts.length];
    out.push(V3.add(a, V3.mul(V3.sub(b, a), t)));
  }
  return out;
}

/* Scale so the farthest point sits at R, so no form swells mid-morph. */
function norm(pts, R) {
  const m = Math.max(...pts.map(V3.len));
  return pts.map((p) => V(...V3.mul(p, R / m)));
}

const shaped = (pts) => norm(resample(pts, 360), 1.32);

const CURVES = {
  /*
    Closed spherical spiral. A true rhumb line coils into the poles forever and
    never closes, so it cannot be a loop; this is its closed relative, winding
    the sphere five times and returning to where it began.
  */
  spherical: () =>
    shaped(
      sample(420, TAU, (th) => [
        Math.sin(th) * Math.cos(5 * th),
        Math.sin(th) * Math.sin(5 * th),
        Math.cos(th)
      ])
    ),

  /*
    Rolfsen 3_1, the trefoil: the (2,3) torus knot, three crossings. The standard
    parametrisation, which viewed down its axis gives the familiar three-lobed
    figure with the over-under crossings evenly spaced.
  */
  trefoil: () =>
    shaped(
      sample(420, TAU, (t) => [
        Math.sin(t) + 2 * Math.sin(2 * t),
        Math.cos(t) - 2 * Math.cos(2 * t),
        -Math.sin(3 * t)
      ])
    ),

  /* Conical rose: the four-petal rose r = cos(2t) lifted onto a cone. */
  conicalRose: () =>
    shaped(
      sample(320, TAU, (t) => {
        const r = Math.cos(2 * t);
        return [
          r * Math.cos(t),
          r * Math.sin(t),
          (1 - Math.abs(r)) * 0.85 - 0.42
        ];
      })
    )
};

/*
  Each curve has one angle where its structure is legible and others where it
  collapses into tangle: the rose reads tipped back so the petals separate and the
  cone shows, the knot needs a three-quarter turn for its five crossings to be
  countable, the spherical spiral wants its poles off-axis. So the viewing angle
  is a property of the shape, blended along with the morph, rather than one
  continuous spin that drags every form through its worst view.
*/
/*
  Five numbers per shape: three for the resting tilt, then how much of the
  continuous turn runs on the y axis versus the object's own z.

  The axis matters as much as the tilt. A trefoil or a rose has a face, and
  turning it about y swings that face edge-on, where the three lobes overlap
  into a tangle and the petals disappear. Turning about its own z instead keeps
  it facing the viewer and rotates it in plane, which is how these forms are
  always drawn. A sphere has no face, so it turns about y.

  Both weights blend along with the shape, so the axis of rotation crosses over
  smoothly instead of switching.
*/
const VIEWS = {
  spherical: [0.34, 0.18, 0.0, 1, 0],
  trefoil: [0.14, 0.0, 0.0, 0, 1],
  conicalRose: [-0.85, 0.12, 0.0, 0, 1],
  ball: [0.42, 0.6, 0.1, 1, 0]
};

const CHAIN = ["spherical", "trefoil", "conicalRose"];
const SECTIONS = ["problem", "how", "proof", "employee", "final"];

function tubeOf(kind, radius) {
  const curve = new THREE.CatmullRomCurve3(
    CURVES[kind](),
    true,
    "catmullrom",
    0.5
  );
  return new THREE.TubeGeometry(curve, TUBULAR, radius, RADIAL, true);
}

/*
  One geometry carrying the first form, with every later form attached as a
  morph target. Normals are morphed alongside positions, otherwise the shading
  stays frozen on the first shape while the silhouette changes underneath it.
*/
function morphGeometry(radius) {
  const base = tubeOf(CHAIN[0], radius);
  base.morphAttributes.position = [];
  base.morphAttributes.normal = [];

  CHAIN.slice(1).forEach((kind) => {
    const g = tubeOf(kind, radius);
    base.morphAttributes.position.push(g.attributes.position);
    base.morphAttributes.normal.push(g.attributes.normal);
    g.dispose();
  });

  return base;
}

/*
  The hero keeps the real ball: three great circles sharing a centre, passing
  through each other rather than joining. Three separate rings cannot morph
  into a single tube, so this one sits outside the chain by design.
*/
function ballGeometry(radius) {
  return [0, 1, 2].map((i) => {
    const ring = new THREE.TorusGeometry(1.35, radius, 22, 150);
    ring.rotateY((i / 3) * Math.PI);
    return ring;
  });
}

/*
  Placement is a scene-space concern, not a DOM one: the canvas covers its
  area and each spot says where a form sits inside it.

  Positions are fractions of the visible half-width and half-height, never
  fixed world units. A narrow viewport sees a narrower slice of the scene, so
  a hardcoded x would walk the flanking forms off screen on a phone while
  leaving them short of the edge on a wide monitor.
*/
/*
  `size` is the form's radius as a fraction of the smaller viewport half-axis,
  so a form is always a known share of the screen. Normalising to a fixed world
  size instead (what a gallery tile wants) makes a form fill most of a laptop
  viewport, which is how the hero ended up 88% of the screen tall.
*/
const HERO_SPOTS = [
  { fx: -0.94, fy: 0.26, size: 0.6, opacity: 0.8 },
  { fx: 0.96, fy: -0.32, size: 0.5, opacity: 0.8, spin: -1 }
];
/* Large enough to be an object rather than an ornament: at this drift speed a
   small form just reads as a stray dot. Diameter lands near half the viewport
   height, and it is cropped by the edges for most of its travel. */
const PIN_SIZE = 0.7;
const PIN_OPACITY = 0.85;

/*
  Where the pinned form sits while each section is centred. It descends steadily
  while sweeping from the right margin across to the left, so the travel reads as
  one long diagonal rather than a fall.

  Both axes stay monotonic: it never doubles back, which is what made the earlier
  side-to-side path feel erratic. The curve comes from pacing instead. The lateral
  steps are small, large, large, small, so the form lingers in each margin and
  crosses the middle quickly, where the content is densest.
*/
const PIN_PATH = [
  { fx: 0.88, fy: 0.34 },
  { fx: 0.78, fy: 0.16 },
  { fx: 0.3, fy: -0.02 },
  { fx: -0.52, fy: -0.18 },
  { fx: -0.74, fy: -0.32 }
];

/* Opacity only. Surface character belongs to the finish, not to the weight. */
const WEIGHTS = { soft: 0.45, solid: 1 };

/*
  Every finish stays inside the one-accent rule: the same blue, differing only
  in how it handles light. Glass and frosted read as blue-tinted clear rather
  than as a second hue.
*/
const FINISHES = {
  gloss: {
    roughness: 0.18,
    clearcoat: 1,
    clearcoatRoughness: 0.1,
    sheen: 0.6,
    sheenColor: 0x9fc2ef,
    envMapIntensity: 1.1
  },
  matte: {
    roughness: 0.92,
    clearcoat: 0,
    sheen: 0.35,
    sheenColor: 0xbcd3ef,
    envMapIntensity: 0.55
  },
  /* Slight roughness keeps it from turning into a mirror ball on a light page. */
  metal: {
    metalness: 1,
    roughness: 0.22,
    clearcoat: 0,
    envMapIntensity: 1.35
  },
  glass: {
    roughness: 0.04,
    transmission: 1,
    thickness: 1.1,
    ior: 1.45,
    clearcoat: 1,
    clearcoatRoughness: 0.06,
    color: 0x7fa9e0,
    envMapIntensity: 1.2
  },
  frosted: {
    roughness: 0.55,
    transmission: 1,
    thickness: 1.4,
    ior: 1.35,
    clearcoat: 0.4,
    color: 0x8fb4e6,
    envMapIntensity: 0.9
  },
  /* Flat and powdery. The one finish with no specular event anywhere on it. */
  chalk: {
    roughness: 1,
    clearcoat: 0,
    sheen: 0,
    envMapIntensity: 0.28
  }
};

function makeMaterial(finish, opacity) {
  const spec = FINISHES[finish] || FINISHES.gloss;
  const m = new THREE.MeshPhysicalMaterial({
    color: spec.color ?? ACCENT,
    metalness: spec.metalness ?? 0,
    roughness: spec.roughness,
    clearcoat: spec.clearcoat ?? 0,
    clearcoatRoughness: spec.clearcoatRoughness ?? 0.2,
    envMapIntensity: spec.envMapIntensity ?? 1
  });
  if (spec.sheen) {
    m.sheen = spec.sheen;
    m.sheenColor = new THREE.Color(spec.sheenColor);
  }
  if (spec.transmission) {
    m.transmission = spec.transmission;
    m.thickness = spec.thickness;
    m.ior = spec.ior;
  }
  /* Transmission already needs the transparent path, so only opacity decides here. */
  m.transparent = true;
  m.opacity = opacity;
  m.depthWrite = opacity > 0.95;
  return m;
}

function makeStage(host, config) {
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
  camera.position.set(0, 0, 6.6);

  const renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: true,
    powerPreference: "low-power"
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearAlpha(0);
  host.appendChild(renderer.domElement);

  /*
    Gloss, metal and glass have nothing to reflect without an environment, and
    read as flat blue plastic. One small PMREM room per renderer fixes that.
  */
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

  scene.add(new THREE.HemisphereLight(0xffffff, 0xd7e2f2, 1.5));
  const key = new THREE.DirectionalLight(0xffffff, 2.6);
  key.position.set(3.5, 5, 6);
  scene.add(key);
  const rim = new THREE.DirectionalLight(ACCENT_DARK, 1.8);
  rim.position.set(-5, -2, -4);
  scene.add(rim);

  let bodies = [];
  let raf = 0;
  let running = false;
  let presence = 1;
  let baseOpacity = 1;
  let anchor = null;
  /* Fixed stages and the hero never call setMorph, so this is the resting angle. */
  let view = VIEWS[config.pin ? CHAIN[0] : "ball"];
  let t = 0;

  /* Geometry and material are rebuilt per variant, so both must be released. */
  function clear() {
    bodies.forEach((b) => {
      scene.remove(b.group);
      b.group.traverse((o) => {
        if (o.isMesh) o.geometry.dispose();
      });
      b.material.dispose();
    });
    bodies = [];
  }

  function build(state) {
    clear();
    const hidden =
      state.weight === "off" || (config.pin ? false : !state.hero);
    if (hidden) {
      renderer.render(scene, camera);
      return;
    }

    const weight = WEIGHTS[state.weight] ?? WEIGHTS.solid;
    const spots = config.pin
      ? [{ ...PIN_PATH[0], size: PIN_SIZE, opacity: PIN_OPACITY }]
      : HERO_SPOTS;

    spots.forEach((spot) => {
      const group = new THREE.Group();
      baseOpacity = weight * spot.opacity;
      const material = makeMaterial(state.finish, baseOpacity);
      const geos = config.pin
        ? [state.morph ? morphGeometry(state.tube) : tubeOf(state.shape, state.tube)]
        : ballGeometry(state.tube);

      /* Normalise across every loop so each shape reads at the same size. */
      let extent = 0;
      const meshes = geos.map((g) => {
        g.computeBoundingSphere();
        const bs = g.boundingSphere;
        extent = Math.max(extent, bs.center.length() + bs.radius);
        const mesh = new THREE.Mesh(g, material);
        group.add(mesh);
        return mesh;
      });

      scene.add(group);
      bodies.push({
        group,
        material,
        meshes,
        spot,
        /* Unit radius: scaling by (fraction * half-axis) gives that exact radius. */
        fit: 1 / extent,
        base: 0,
        turn: 0,
        spin: spot.spin || 1,
        phase: spot.fx * 4
      });
    });

    if (!config.pin) view = VIEWS.ball;
    else if (!state.morph) view = VIEWS[state.shape] || VIEWS[CHAIN[0]];
    bodies.forEach(applyView);
    layout();
    renderer.render(scene, camera);
  }

  /* Converts each form's fractional placement into world units for the current aspect. */
  function layout() {
    const halfH = Math.tan((camera.fov * Math.PI) / 360) * camera.position.z;
    const halfW = halfH * camera.aspect;
    /* Height is the reference, capped by width so a form never outgrows a
       narrow viewport. Sizing off raw width instead shrinks it to nothing in
       portrait; a loose cap lets it swamp a phone's width. Landscape viewports
       are always bound by height, so this only bites on narrow screens. */
    const ref = Math.min(halfH, halfW);

    bodies.forEach((b) => {
      const at = anchor || b.spot;
      b.base = at.fy * halfH;
      b.group.position.set(at.fx * halfW, b.base, 0);
      b.group.scale.setScalar(b.spot.size * ref * b.fit * presence);
    });
  }

  /*
    Maps a position along the chain onto morph influences. Within a segment the
    blend is a crossfade between two neighbouring forms, so only ever two
    influences are non-zero and they sum to one.
  */
  function setMorph(f) {
    const i = Math.min(Math.floor(f), CHAIN.length - 2);
    const local = snap(clamp01(f - i));

    /* The presentation angle crosses over with the shape it belongs to. */
    const from = VIEWS[CHAIN[i]] || VIEWS.ball;
    const to = VIEWS[CHAIN[i + 1]] || from;
    view = from.map((v, k) => v + (to[k] - v) * local);

    bodies.forEach((b) => {
      b.meshes.forEach((m) => {
        const infl = m.morphTargetInfluences;
        if (!infl) return;
        infl.fill(0);
        if (i > 0) infl[i - 1] = 1 - local;
        infl[i] = local;
      });
      applyView(b);
    });
  }

  /*
    The form turns continuously, but only about its own vertical axis. The tilt
    (x and z) stays fixed per shape, and that is the part carrying legibility: the
    rose has to stay tipped back for its petals to separate and its cone to read,
    the knot has to keep its crossings off-edge. Turning all three axes is what
    dragged shapes through views where they collapsed into tangle.
  */
  function applyView(b) {
    /* Euler XYZ applies z first, so the z term turns the form about its own
       axis and the x/y terms then tilt the result. */
    b.group.rotation.set(
      view[0] + Math.sin(t * 0.4 + b.phase) * 0.05,
      view[1] + b.turn * view[3],
      view[2] + b.turn * view[4]
    );
  }

  function resize() {
    const w = host.clientWidth;
    const h = host.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    layout();
    renderer.render(scene, camera);
  }

  /*
    Idle motion is one slow rotation plus a barely-there rise and fall. The
    tumble and bob were large enough to compete with the scroll-driven drift,
    which is what made the whole thing feel busy rather than alive.
  */
  function frame() {
    t += 0.004;
    bodies.forEach((b) => {
      b.turn += 0.0016 * b.spin;
      applyView(b);
      b.group.position.y = b.base + Math.sin(t * 0.5 + b.phase) * 0.04;
    });
    renderer.render(scene, camera);
    raf = requestAnimationFrame(frame);
  }

  resize();
  new ResizeObserver(resize).observe(host);
  requestAnimationFrame(() => host.classList.add("is-ready"));

  /*
    The pinned stage is on screen for the whole page, so it runs whenever the
    document is visible rather than gating on an IntersectionObserver.
  */
  function setRunning(on) {
    if (on && !running && !reduceMotion && bodies.length) {
      running = true;
      frame();
    } else if (!on && running) {
      running = false;
      cancelAnimationFrame(raf);
    }
  }

  return {
    build,
    config,
    host,
    setRunning,
    /* Scroll drives where the form sits, how far along the chain it is, and how present. */
    update(chainPos, p, at) {
      presence = Math.max(p, 0.001);
      anchor = at || null;
      /* Fade with the scale, otherwise a shrunken form still reads at full ink. */
      bodies.forEach((b) => {
        b.material.opacity = baseOpacity * clamp01(p * 1.15);
      });
      if (config.pin) setMorph(chainPos);
      layout();
      if (!running) renderer.render(scene, camera);
    }
  };
}

let heroStage = null;
let pinStage = null;
let sectionEls = [];
let started = false;

/* Locked in: soft weight, chalk finish, 0.12 tube. */
const state = {
  weight: "soft",
  finish: "chalk",
  tube: 0.12,
  morph: true,
  hero: true
};

function pageProgress() {
  const mid = window.innerHeight / 2;
  const centres = sectionEls.map((el) => {
    if (!el) return Infinity;
    const r = el.getBoundingClientRect();
    return r.top + r.height / 2;
  });
  const last = centres.length - 1;
  if (last < 1) return 0;

  if (mid <= centres[0]) return 0;
  for (let i = 0; i < last; i++) {
    if (mid <= centres[i + 1]) {
      const span = centres[i + 1] - centres[i] || 1;
      return (i + (mid - centres[i]) / span) / last;
    }
  }
  return 1;
}

/*
  Two separate curves off the hero's bottom edge, deliberately not one shared
  number. The hero pair starts shrinking as soon as the page moves, while the
  pinned form stays at zero until the hero is more than half gone. A single
  crossfade had the pin at 60% while the hero still filled most of the screen.
*/
function heroCurves() {
  const host = heroStage && heroStage.host;
  if (!host) return { hero: 0, pin: 1 };
  const vh = window.innerHeight;
  const bottom = host.getBoundingClientRect().bottom / vh;
  return {
    hero: clamp01((0.95 - bottom) / 0.55),
    /* Ramps across roughly a full screen of scrolling, so the form grows in
       gradually instead of snapping to full size just past the hero. */
    pin: clamp01((0.55 - bottom) / 0.95)
  };
}

/*
  The pinned form travels along the anchors as the chain advances, on a
  Catmull-Rom spline rather than straight segments.

  Two things this buys. Velocity stays continuous through each anchor, so the
  deliberately uneven lateral pacing does not show up as a jolt where the steps
  change size. And easing into and out of every anchor is avoided, which would
  stop the drift dead five times down the page. Endpoints are duplicated so the
  curve starts and ends exactly on the first and last anchor.
*/
function splineAt(pts, key, i, t) {
  const at = (n) => pts[Math.min(Math.max(n, 0), pts.length - 1)][key];
  const p0 = at(i - 1);
  const p1 = at(i);
  const p2 = at(i + 1);
  const p3 = at(i + 2);
  return (
    0.5 *
    (2 * p1 +
      (p2 - p0) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
      (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
  );
}

/*
  The chain does not start advancing the moment the page moves, and it finishes
  before the page ends. Without the lead-in the first shape is already half
  morphed while it is still scaling in, so it is never seen whole; the tail does
  the same for the last shape at the foot of the page.
*/
const CHAIN_LEAD = 0.22;
/* The tail is sized so the last shape is fully formed by the time the employee
   section reaches the middle of the viewport, not still arriving there. */
const CHAIN_TAIL = 0.26;
function chainAt(u) {
  return (
    clamp01((u - CHAIN_LEAD) / (1 - CHAIN_LEAD - CHAIN_TAIL)) *
    (CHAIN.length - 1)
  );
}

function pinAnchor(u) {
  const f = u * (PIN_PATH.length - 1);
  const i = Math.min(Math.floor(f), PIN_PATH.length - 2);
  const t = clamp01(f - i);
  return {
    fx: splineAt(PIN_PATH, "fx", i, t),
    fy: splineAt(PIN_PATH, "fy", i, t)
  };
}

function sync() {
  const curve = heroCurves();

  if (heroStage) {
    const hp = easeOut(1 - curve.hero);
    heroStage.update(0, hp);
    heroStage.setRunning(state.hero && hp > 0.02);
  }
  if (pinStage) {
    const pin = easeOut(curve.pin);
    const u = pageProgress();
    pinStage.update(chainAt(u), pin, pinAnchor(u));
    pinStage.setRunning(pin > 0.02);
  }
}

function build() {
  if (heroStage) heroStage.build(state);
  if (pinStage) pinStage.build(state);
  sync();
}

/* One scroll listener drives both stages, rAF-throttled. */
let queued = false;
function onScroll() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => {
    queued = false;
    sync();
  });
}

/*
  Called by the page once React has mounted. Idempotent: a second call rebuilds
  against the current layout rather than stacking another set of canvases, so a
  hot re-render or a late font load cannot leave two motifs running.
*/
function init() {
  sectionEls = Array.from(document.querySelectorAll("[data-motif-section]"));

  const heroHost = document.querySelector("[data-motif-hero]");
  if (heroHost && !heroStage) heroStage = makeStage(heroHost, { pin: false });

  if (!pinStage) {
    const pinHost = document.createElement("div");
    pinHost.className = "cd-motif cd-motif--pin";
    pinHost.setAttribute("aria-hidden", "true");
    document.body.appendChild(pinHost);
    pinStage = makeStage(pinHost, { pin: true });
  }

  build();

  if (!started) {
    started = true;
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
  }
}

window.CDMotif = { init };