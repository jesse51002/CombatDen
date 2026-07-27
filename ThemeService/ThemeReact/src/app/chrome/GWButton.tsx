// Ports ../../../../../LandingPage/hifi/chrome.jsx — `GWButton`.
//
// THE INLINE `style={{}}` OBJECT IS VERBATIM AND MUST STAY THAT WAY. This
// component and ./GWNav.tsx are the site chrome shared with the marketing page;
// keeping their style objects byte-comparable with chrome.jsx is what lets a
// future landing-page restyle be diffed straight across. Converting them to a
// CSS Module would make that impossible. Everything else in this app is a CSS
// Module (see ../../../CLAUDE.md).
//
// TWO DEVIATIONS, both forced by TypeScript and both style-neutral:
//   1. chrome.jsx picks its element with `const Tag = href ? 'a' : 'button'`
//      and spreads `extra`. A dynamic tag with a union of prop types does not
//      typecheck, so the two branches are written out. The style object, the
//      children, and the `target`/`rel`/`onClick` wiring are unchanged.
//   2. `COPY` is not a global here; the default label is imported.

import type { CSSProperties, MouseEventHandler } from 'react';

import { GW } from '../tokens/gw';

import { CTA_DEMO } from './navCopy';

export interface GWButtonProps {
  label?: string;
  size?: 'sm' | 'md' | 'lg';
  arrow?: boolean;
  onClick?: MouseEventHandler<HTMLButtonElement>;
  href?: string;
  kind?: 'primary' | 'secondary';
  newTab?: boolean;
}

export function GWButton({
  label = CTA_DEMO,
  size = 'md',
  arrow = true,
  onClick,
  href,
  kind = 'primary',
  newTab = true,
}: GWButtonProps) {
  const pad = size === 'lg' ? '15px 26px' : size === 'sm' ? '9px 16px' : '13px 22px';
  const fs = size === 'lg' ? 16 : size === 'sm' ? 14 : 15;
  const primary = kind === 'primary';
  const style: CSSProperties = {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 9,
    border: primary ? 'none' : `1px solid ${GW.line}`,
    cursor: 'pointer',
    whiteSpace: 'nowrap',
    fontFamily: GW.sans,
    fontSize: fs,
    fontWeight: 600,
    letterSpacing: -0.1,
    color: primary ? '#fff' : GW.ink,
    padding: pad,
    borderRadius: 12,
    textDecoration: 'none',
    background: primary ? `linear-gradient(180deg, ${GW.accent}, ${GW.accentDark})` : GW.surface,
    boxShadow: primary
      ? '0 1px 2px rgba(15,45,95,0.32), 0 8px 22px -6px rgba(30,80,160,0.5), inset 0 1px 0 rgba(255,255,255,0.28)'
      : '0 1px 2px rgba(20,22,40,0.05)',
  };
  const body = (
    <>
      {label}
      {arrow && (
        <svg
          width="15"
          height="15"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.9"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M3 8h10M9 4l4 4-4 4" />
        </svg>
      )}
    </>
  );
  if (href) {
    return (
      <a href={href} {...(newTab ? { target: '_blank', rel: 'noopener' } : {})} style={style}>
        {body}
      </a>
    );
  }
  return (
    <button type="button" onClick={onClick} style={style}>
      {body}
    </button>
  );
}
