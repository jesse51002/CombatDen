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
  sans: '"Geist", "Inter", system-ui, -apple-system, sans-serif',
  mono: '"Geist Mono", ui-monospace, "SF Mono", Menlo, monospace',
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

Object.assign(window, { GW, BRAND, gwRgba, GWDotGrid, GWGlow });
