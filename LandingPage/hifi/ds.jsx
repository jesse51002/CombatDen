// ds.jsx — design system foundation: tokens + atmosphere primitives.
// Ported from the Claude Design handoff (ds3.jsx). The shared chrome
// (GWNav / GWButton / GWDisclaimer) lives in chrome.jsx; copy lives in copy.jsx.
// Exports GW (tokens), BRAND, GWDotGrid, GWGlow to window.

// Brand name. Single source of truth — rendered by the nav wordmark, footer,
// and <title>. Swap this one string to rebrand the whole site.
const BRAND = 'CombatDen';

const GW = {
  // ground + surfaces (light system)
  bg: '#f3f5f8',
  bgAlt: '#eef1f6',
  surface: '#ffffff',
  // ink ramp
  ink: '#16181d',
  inkSoft: '#565b66',
  inkFaint: '#878d99',
  // hairlines
  line: 'rgba(20,22,30,0.09)',
  lineSoft: 'rgba(20,22,30,0.06)',
  // accent (blue) + gradient partner + soft tint + atmosphere glows
  accent: '#2A67BD',
  accentDark: '#1F5099',
  accentSoft: '#E8F0FB',
  accentGlow: 'rgba(42,103,189,0.18)',
  cyanGlow: 'oklch(0.72 0.15 215 / 0.13)',
  // type
  sans: '"Schibsted Grotesk", system-ui, -apple-system, sans-serif',
  mono: '"DM Mono", ui-monospace, "SF Mono", Menlo, monospace',
  // layout
  maxW: 1180,
};

// hex -> rgba helper (shared by mocks + theme preview).
function gwRgba(hex, a) {
  const h = hex.replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

// Faint dot-grid backdrop, masked to fade out. Pure CSS, no images.
function GWDotGrid({ opacity = 1, color = 'rgba(20,22,40,0.05)', fade = 'radial-gradient(120% 100% at 50% 0%, #000 40%, transparent 85%)' }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, opacity, pointerEvents: 'none', zIndex: 0,
      backgroundImage: `radial-gradient(${color} 1px, transparent 1px)`,
      backgroundSize: '22px 22px',
      maskImage: fade, WebkitMaskImage: fade,
    }}></div>
  );
}

// A positioned radial-glow blob. Decorative atmosphere behind sections.
function GWGlow({ style }) {
  return <div style={{ position: 'absolute', borderRadius: '50%', pointerEvents: 'none', zIndex: 0, ...style }}></div>;
}

// Landing-page video rule (see LandingPage/CLAUDE.md): a <video> plays only while
// it's on screen and restarts from the start when it scrolls out of view, so no clip
// ever plays off-screen. Attach a ref to the <video> (drop `autoPlay`) and call this
// hook. `onVisible(bool)` is optional, for callers that also need the in-view state.
// Shared scroll-reveal gate. An animation/video starts only once it has scrolled
// ~25% up into the viewport, not the instant its top edge peeks in. Implemented as
// a bottom rootMargin (the bottom 25% of the viewport doesn't count as "in view"),
// which is height-independent — it works for tall phone mockups where an element
// ratio threshold would misfire. Reused by every scroll-triggered animation (the
// videos, the §7 count-up, the §6 loyalty loops, the hero cycle) so they all reveal
// at the same point.
const IN_VIEW_MARGIN = '0px 0px -25% 0px';

function useVideoInView(videoRef, onVisible) {
  React.useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const io = new IntersectionObserver((entries) => {
      const vis = entries[0].isIntersecting;
      if (vis) v.play().catch(() => {});
      else { v.pause(); v.currentTime = 0; }
      if (onVisible) onVisible(vis);
    }, { rootMargin: IN_VIEW_MARGIN, threshold: 0 });
    io.observe(v);
    return () => io.disconnect();
  }, []);
}

// Mobile breakpoint (see LandingPage/CLAUDE.md "Mobile responsiveness"). The page
// is 100% inline styles, so a <style> media query can't override them without
// !important — responsiveness is JS-driven instead. `useIsMobile()` returns true
// at phone widths. Lazy-init from matchMedia so the first paint is already correct
// (no flash), and listen only to the `change` event so a re-render fires ONLY when
// the viewport crosses the breakpoint — never on scroll/resize within it, so the
// effect-driven video/animation state is never disturbed. Sections call this and
// swap a few style values (grid columns, padding) on the result.
const MOBILE_Q = '(max-width: 768px)';
function useIsMobile(q = MOBILE_Q) {
  const [m, setM] = React.useState(() => window.matchMedia(q).matches);
  React.useEffect(() => {
    const mq = window.matchMedia(q);
    const h = (e) => setM(e.matches);
    mq.addEventListener('change', h);
    return () => mq.removeEventListener('change', h);
  }, [q]);
  return m;
}

// The agent's channels, as hues. This is the ONE documented exception to
// DESIGN.md's One-Accent Rule: these are agent handles, not brand. Matched oklch
// lightness and chroma so they read as a single categorical set, and chosen to
// dodge both palette anti-references (no mint/teal wellness green, no
// indigo/violet AI slop). Shared, because the AI page names the same channels in
// two places (the §4 cards and the §5 log) and they have to agree.
const AGENT_HUES = {
  chat: 258, member: 218, competition: 18, growth: 72,
  revenue: 145, reputation: 300, schedule: 45, industry: 180,
};

// Scroll reveal. Elements marked `data-reveal` start 20px low and transparent and
// settle once they scroll into view, at the same reveal point as every other
// animation (IN_VIEW_MARGIN). Stagger a group by setting `--rd` per element.
//
// Two properties worth keeping. The `.anim` class is only added when motion is
// allowed, and the CSS keys everything off it, so under reduced motion the markup
// stays at its natural visible state rather than being animated to visible. And an
// element is unobserved once revealed, so a reveal never replays on the way back up.
//
// The CSS lives in the page's own <style> block (it needs a descendant selector,
// which an inline style cannot express).
function useReveal(rootRef) {
  React.useEffect(() => {
    const root = rootRef && rootRef.current ? rootRef.current : document;
    const els = Array.from(root.querySelectorAll('[data-reveal]'));
    if (!els.length) return;

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      els.forEach((el) => el.classList.add('is-in'));
      return;
    }
    document.documentElement.classList.add('anim');

    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        e.target.classList.add('is-in');
        io.unobserve(e.target);
      });
    }, { rootMargin: IN_VIEW_MARGIN });

    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
}

Object.assign(window, { GW, BRAND, gwRgba, GWDotGrid, GWGlow, useVideoInView, IN_VIEW_MARGIN, useIsMobile, MOBILE_Q, useReveal, AGENT_HUES });
