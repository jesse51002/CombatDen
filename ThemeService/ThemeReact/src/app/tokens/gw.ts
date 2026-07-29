// Ports ../../../../../LandingPage/hifi/ds.jsx — the `GW` token object, the
// `BRAND` string and the `gwRgba` helper, VERBATIM. Values are unchanged; the
// only additions are TypeScript types and `as const`.
//
// This is the LANDING PAGE's design system, and it is the source of truth for
// the site chrome (GWNav / GWButton in ../chrome/). The CRM's light
// `DesignConstants` values live next door in ./adminTokens.ts and are the
// source of truth for everything BELOW the nav. The two overlap by design (the
// CRM light palette was derived from GW), but they are separate modules with
// separate CSS-variable namespaces — `--gw-*` here, `--adm-*` there.
//
// The showcase island's own tokens are a THIRD system that must never meet
// either of these (eslint.config.js Gates 2a/2b).

/** Brand name — ds.jsx line 8. Rendered by the nav wordmark. */
export const BRAND = 'CombatDen';

export const GW = {
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
} as const;

/** hex -> rgba helper (shared by mocks + theme preview). */
export function gwRgba(hex: string, a: number): string {
  const h = hex.replace('#', '');
  const n = parseInt(
    h.length === 3
      ? h
          .split('')
          .map((c) => c + c)
          .join('')
      : h,
    16,
  );
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}
